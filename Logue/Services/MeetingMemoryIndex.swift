import Foundation
import os.log
import SQLite3

/// On-device full-text search index for cross-meeting memory.
/// Uses SQLite FTS5 to index meeting transcripts, summaries, and keywords,
/// enabling the AI chat to retrieve relevant context from past meetings.
///
/// Thread safety: The `db` handle is `nonisolated(unsafe)` but is ONLY accessed
/// from `dbQueue` (serial). All public methods dispatch onto `dbQueue` before
/// touching `db`. The `nonisolated` helper methods include assertions to enforce this.
@MainActor
final class MeetingMemoryIndex {
    static let shared = MeetingMemoryIndex()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MeetingMemoryIndex")
    /// All `db` access MUST go through `dbQueue` — never access `db` directly from @MainActor.
    /// The nonisolated(unsafe) marker is required because DispatchQueue serialization
    /// provides the actual thread safety, not actor isolation.
    private let dbQueue = DispatchQueue(label: "com.bitwize.logue.memoryIndex", qos: .userInitiated)
    nonisolated(unsafe) private var db: OpaquePointer?

    /// Whether the index has been built at least once this session.
    private(set) var isIndexReady = false

    private static let dbURL: URL = {
        let dir = URL.applicationSupportDirectory
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            os_log(.error, "Failed to create MeetingMemoryIndex directory: %{public}@", error.localizedDescription)
        }
        return dir.appending(path: "meeting_memory.sqlite")
    }()

    private init() {
        openDatabase()
    }

    // B8: Use async to prevent potential deadlock when deinit runs on MainActor
    deinit {
        let db = self.db
        dbQueue.async {
            if let db {
                sqlite3_close(db)
            }
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let path = Self.dbURL.path(percentEncoded: false)
        dbQueue.sync { [self] in
            if sqlite3_open(path, &db) != SQLITE_OK {
                logger.error("Failed to open memory index database")
                return
            }

            // Apply file protection — index is rebuilt from encrypted meetings.json on each launch
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: path
            )

            // Create FTS5 virtual table
            let createSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS meeting_fts USING fts5(
                meeting_id UNINDEXED,
                title,
                transcript,
                summary,
                keywords,
                action_items,
                tokenize='porter unicode61'
            );
            """
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown"
                logger.error("Failed to create FTS5 table: \(msg, privacy: .public)")
                sqlite3_free(errMsg)
            }

            // Metadata table to track indexed meetings
            let metaSQL = """
            CREATE TABLE IF NOT EXISTS index_meta (
                meeting_id TEXT PRIMARY KEY,
                modified_at REAL NOT NULL
            );
            """
            if sqlite3_exec(db, metaSQL, nil, nil, &errMsg) != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown"
                logger.error("Failed to create meta table: \(msg, privacy: .public)")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Indexing

    /// Incrementally sync the index with the current meetings array.
    /// Only re-indexes meetings that changed since last index; removes deleted ones.
    func rebuildIndex(from meetings: [MeetingNote]) {
        let indexable = meetings.filter { !$0.isTrashed && !$0.segments.isEmpty }
        dbQueue.async { [weak self] in
            guard let self, let db else { return }

            // Load existing index timestamps: meetingID → modifiedAt
            var existingMeta: [String: Double] = [:]
            let metaQuery = "SELECT meeting_id, modified_at FROM index_meta;"
            var metaStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, metaQuery, -1, &metaStmt, nil) == SQLITE_OK {
                while sqlite3_step(metaStmt) == SQLITE_ROW {
                    if let idCStr = sqlite3_column_text(metaStmt, 0) {
                        let id = String(cString: idCStr)
                        let modifiedAt = sqlite3_column_double(metaStmt, 1)
                        existingMeta[id] = modifiedAt
                    }
                }
                sqlite3_finalize(metaStmt)
            }

            let currentIDs = Set(indexable.map(\.id.uuidString))
            var insertedCount = 0
            var removedCount = 0

            // Remove meetings no longer in the store
            for existingID in existingMeta.keys where !currentIDs.contains(existingID) {
                deleteMeeting(id: existingID, db: db)
                removedCount += 1
            }

            // Insert or update meetings that changed
            for meeting in indexable {
                let idStr = meeting.id.uuidString
                let meetingModified = meeting.modifiedAt.timeIntervalSince1970
                if let existingModified = existingMeta[idStr], abs(existingModified - meetingModified) < 0.001 {
                    continue // Already indexed and unchanged
                }
                deleteMeeting(id: idStr, db: db)
                insertMeeting(meeting, db: db)
                insertedCount += 1
            }

            Task { @MainActor [weak self] in
                self?.isIndexReady = true
                self?.logger
                    .info("Memory index synced: \(insertedCount) updated, \(removedCount) removed, \(indexable.count - insertedCount) unchanged")
            }
        }
    }

    /// Index or update a single meeting. Called after summaries/transcripts change.
    func indexMeeting(_ meeting: MeetingNote) {
        guard !meeting.isTrashed, !meeting.segments.isEmpty else {
            removeMeeting(id: meeting.id)
            return
        }
        dbQueue.async { [weak self] in
            guard let self, let db else { return }

            // Remove old entry
            deleteMeeting(id: meeting.id.uuidString, db: db)
            // Insert updated
            insertMeeting(meeting, db: db)

            logger.debug("Indexed meeting: \(meeting.title, privacy: .private)")
        }
    }

    /// Remove a meeting from the index.
    func removeMeeting(id: UUID) {
        let idStr = id.uuidString
        dbQueue.async { [weak self] in
            guard let self, let db else { return }
            deleteMeeting(id: idStr, db: db)
        }
    }

    nonisolated private func insertMeeting(_ meeting: MeetingNote, db: OpaquePointer) {
        dispatchPrecondition(condition: .onQueue(dbQueue))
        let insertFTS = "INSERT INTO meeting_fts (meeting_id, title, transcript, summary, keywords, action_items) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertFTS, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let idStr = meeting.id.uuidString
        let fullTranscript = meeting.segments.map(\.text).joined(separator: " ")
        let transcript = String(fullTranscript.prefix(10000))
        let summary = meeting.summary ?? ""
        let keywords = meeting.topicKeywords.joined(separator: " ")
        let actions = meeting.actionItems.map(\.title).joined(separator: " ")

        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (meeting.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (transcript as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (summary as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (keywords as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (actions as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.warning("Failed to insert meeting into FTS index: \(meeting.id)")
        }

        // Update meta
        let metaSQL = "INSERT OR REPLACE INTO index_meta (meeting_id, modified_at) VALUES (?, ?);"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, (idStr as NSString).utf8String, -1, nil)
            sqlite3_bind_double(metaStmt, 2, meeting.modifiedAt.timeIntervalSince1970)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }
    }

    nonisolated private func deleteMeeting(id: String, db: OpaquePointer) {
        dispatchPrecondition(condition: .onQueue(dbQueue))
        let deleteSQL = "DELETE FROM meeting_fts WHERE meeting_id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        let metaSQL = "DELETE FROM index_meta WHERE meeting_id = ?;"
        if sqlite3_prepare_v2(db, metaSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Search

    /// Search for meetings related to a query. Returns up to `limit` results ranked by relevance.
    func search(query: String, excludingMeetingID: UUID? = nil, limit: Int = 5) async -> [SearchResult] {
        let cleaned = sanitizeFTSQuery(query)
        guard !cleaned.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            searchSync(cleaned: cleaned, excludingMeetingID: excludingMeetingID, limit: limit) { results in
                continuation.resume(returning: results)
            }
        }
    }

    private func searchSync(cleaned: String, excludingMeetingID: UUID?, limit: Int, completion: @escaping @Sendable ([SearchResult]) -> Void) {
        var results: [SearchResult] = []

        dbQueue.async { [weak self] in
            guard let self, let db else {
                completion([])
                return
            }

            // FTS5 match query with BM25 ranking
            let hasExclude = excludingMeetingID != nil
            var sql = """
            SELECT meeting_id, title, snippet(meeting_fts, 2, '>>>', '<<<', '...', 40) as transcript_snippet,
                   snippet(meeting_fts, 3, '>>>', '<<<', '...', 40) as summary_snippet,
                   bm25(meeting_fts, 0.0, 2.0, 1.0, 3.0, 2.0, 1.5) as rank
            FROM meeting_fts
            WHERE meeting_fts MATCH ?
            """

            if hasExclude {
                sql += " AND meeting_id != ?"
            }

            sql += " ORDER BY rank LIMIT ?;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("Failed to prepare search query")
                completion([])
                return
            }
            defer { sqlite3_finalize(stmt) }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(stmt, paramIndex, (cleaned as NSString).utf8String, -1, nil)
            paramIndex += 1

            if let excludeID = excludingMeetingID {
                let idStr = excludeID.uuidString
                sqlite3_bind_text(stmt, paramIndex, (idStr as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            sqlite3_bind_int(stmt, paramIndex, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCStr = sqlite3_column_text(stmt, 0),
                      let titleCStr = sqlite3_column_text(stmt, 1)
                else { continue }

                let meetingID = String(cString: idCStr)
                let title = String(cString: titleCStr)
                let transcriptSnippet = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let summarySnippet = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let rank = sqlite3_column_double(stmt, 4)

                if let uuid = UUID(uuidString: meetingID) {
                    results.append(SearchResult(
                        meetingID: uuid,
                        title: title,
                        transcriptSnippet: transcriptSnippet,
                        summarySnippet: summarySnippet,
                        relevanceScore: -rank // BM25 returns negative (lower = better)
                    ))
                }
            }

            completion(results)
        }
    }

    /// Build a cross-meeting context string for injecting into the AI chat prompt.
    /// Fetches full summaries and relevant transcript excerpts from past meetings.
    func buildCrossMeetingContext(
        for query: String,
        currentMeetingID: UUID,
        meetings: [MeetingNote]
    ) async -> String? {
        let results = await search(query: query, excludingMeetingID: currentMeetingID, limit: 3)
        guard !results.isEmpty else { return nil }

        var contextParts: [String] = []

        for result in results {
            guard let meeting = meetings.first(where: { $0.id == result.meetingID }) else { continue }

            var part = "### \(meeting.title)"
            part += " (\(meeting.createdAt.formatted(date: .abbreviated, time: .omitted)))"

            if let summary = meeting.summary, !summary.isEmpty {
                part += "\nSummary: \(String(summary.prefix(300)))"
            }

            let pendingActions = meeting.actionItems.filter { !$0.isCompleted }
            if !pendingActions.isEmpty {
                let actionList = pendingActions.prefix(3).map(\.title).joined(separator: "; ")
                part += "\nPending actions: \(actionList)"
            }

            if !result.transcriptSnippet.isEmpty {
                let cleaned = result.transcriptSnippet
                    .replacingOccurrences(of: ">>>", with: "**")
                    .replacingOccurrences(of: "<<<", with: "**")
                part += "\nRelevant excerpt: \(cleaned)"
            }

            contextParts.append(part)
        }

        guard !contextParts.isEmpty else { return nil }

        return """
        RELATED PAST MEETINGS:
        \(contextParts.joined(separator: "\n\n"))
        """
    }

    /// Search returning only matching meeting UUIDs (lightweight for view filtering).
    func searchMatchingIDs(query: String, limit: Int = 50) async -> Set<UUID> {
        let cleaned = sanitizeFTSQuery(query)
        guard !cleaned.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let self, let db else {
                    continuation.resume(returning: [])
                    return
                }

                let sql = "SELECT meeting_id FROM meeting_fts WHERE meeting_fts MATCH ? LIMIT ?;"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, (cleaned as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit))

                var ids: Set<UUID> = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idCStr = sqlite3_column_text(stmt, 0),
                       let uuid = UUID(uuidString: String(cString: idCStr))
                    {
                        ids.insert(uuid)
                    }
                }
                continuation.resume(returning: ids)
            }
        }
    }

    // MARK: - Helpers

    /// Sanitize user input for FTS5 MATCH queries.
    private func sanitizeFTSQuery(_ query: String) -> String {
        // Extract meaningful words, ignore very short ones and FTS operators
        let ftsOperators: Set = ["and", "or", "not", "near"]
        let words = query
            .components(separatedBy: .alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count > 2 && !ftsOperators.contains($0) }

        guard !words.isEmpty else { return "" }

        // Use OR-joined terms for broader matching
        return words.joined(separator: " OR ")
    }

    // MARK: - Types

    struct SearchResult {
        let meetingID: UUID
        let title: String
        let transcriptSnippet: String
        let summarySnippet: String
        let relevanceScore: Double
    }
}
