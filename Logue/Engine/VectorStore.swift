import Foundation
import os.log
import SQLite3

// MARK: - Public Types

/// One indexable chunk to be stored in the vector store.
struct VectorChunk {
    /// Position of this chunk within the parent item (0-based). Use `-1` to indicate
    /// "the whole item" (e.g. a one-shot memory).
    let chunkIdx: Int
    let chunkText: String
    /// L2-normalized embedding produced by `EmbeddingService`.
    let embedding: [Float]
    /// Optional JSON-friendly metadata. Stored as JSON in the `metadata` column.
    let metadata: [String: String]?

    init(
        chunkIdx: Int,
        chunkText: String,
        embedding: [Float],
        metadata: [String: String]? = nil
    ) {
        self.chunkIdx = chunkIdx
        self.chunkText = chunkText
        self.embedding = embedding
        self.metadata = metadata
    }
}

/// One search result row.
struct VectorHit {
    let namespace: String
    let itemID: String
    let chunkIdx: Int
    let chunkText: String
    let metadata: [String: String]?
    /// Cosine similarity in [-1, 1] (assuming both vectors are L2-normalized).
    let score: Float
}

// MARK: - VectorStore

/// SQLite-backed vector store for semantic retrieval. Stores raw `[Float]` embeddings
/// as blobs alongside chunk text + metadata, keyed by `(namespace, item_id, chunk_idx)`.
///
/// Top-K search uses brute-force cosine over the namespace — adequate up to
/// ~50K chunks. If we ever need more, we can add HNSW or another ANN index.
///
/// Used by:
/// - **Phase 3 (Memory)** — namespace `"memory"`, one chunk per memory.
/// - **Phase 4 (Semantic RAG)** — namespace `"meeting"` / `"document"`, multiple chunks per item.
/// - **Phase 11 (Deep Research)** — same namespaces as Phase 4.
actor VectorStore {
    static let shared = VectorStore()

    // Extension-visible: +Graph — needed for graph schema and accessor methods.
    var db: OpaquePointer?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "VectorStore")

    /// Database location. Created lazily under Application Support.
    private static let dbURL: URL = {
        let dir = URL.applicationSupportDirectory
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Vectors", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            os_log(.error, "Failed to create VectorStore directory: %{public}@", error.localizedDescription)
        }
        return dir.appending(path: "vectors.sqlite")
    }()

    init() {
        // Open the database synchronously here. Inlining (rather than calling an
        // actor-isolated method from `init`) avoids the Swift-6 isolation warning
        // about referencing actor methods from a nonisolated init context.
        Self.openDatabaseInto(&db, logger: logger)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema

    nonisolated private static func openDatabaseInto(_ db: inout OpaquePointer?, logger: Logger) {
        let path = Self.dbURL.path(percentEncoded: false)
        if sqlite3_open(path, &db) != SQLITE_OK {
            logger.error("Failed to open VectorStore database")
            return
        }

        // File protection — vectors are reproducible from encrypted meeting/doc data,
        // but the chunk text itself can contain personal info. Treat as sensitive.
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: path
            )
        } catch {
            logger.warning("Could not set file protection on vectors.sqlite: \(error.localizedDescription, privacy: .public)")
        }

        let createSQL = """
        CREATE TABLE IF NOT EXISTS vectors (
            namespace TEXT NOT NULL,
            item_id TEXT NOT NULL,
            chunk_idx INTEGER NOT NULL,
            chunk_text TEXT NOT NULL,
            embedding BLOB NOT NULL,
            metadata TEXT,
            created_at REAL NOT NULL,
            PRIMARY KEY(namespace, item_id, chunk_idx)
        );
        CREATE INDEX IF NOT EXISTS idx_vectors_namespace ON vectors(namespace);
        CREATE INDEX IF NOT EXISTS idx_vectors_item ON vectors(namespace, item_id);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            logger.error("Failed to create vectors table: \(msg, privacy: .public)")
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Public API

    /// Upserts the chunks for `(namespace, itemID)`. Replaces any existing chunks
    /// for that item so re-indexing is idempotent.
    func upsert(namespace: String, itemID: String, chunks: [VectorChunk]) {
        guard let db else { return }
        // Wipe existing chunks for this item, then insert fresh.
        let deleteSQL = "DELETE FROM vectors WHERE namespace = ? AND item_id = ?"
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, namespace, -1, Self.sqliteTransient)
            sqlite3_bind_text(del, 2, itemID, -1, Self.sqliteTransient)
            if sqlite3_step(del) != SQLITE_DONE {
                logger.error("VectorStore delete-before-upsert failed for \(namespace, privacy: .public)/\(itemID, privacy: .private)")
            }
        }
        sqlite3_finalize(del)

        let insertSQL = """
        INSERT INTO vectors(namespace, item_id, chunk_idx, chunk_text, embedding, metadata, created_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        """
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let now = Date.now.timeIntervalSince1970
        for chunk in chunks {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, namespace, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, itemID, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 3, Int32(chunk.chunkIdx))
            sqlite3_bind_text(stmt, 4, chunk.chunkText, -1, Self.sqliteTransient)

            let blob = Self.floatsToData(chunk.embedding)
            blob.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    sqlite3_bind_blob(stmt, 5, base, Int32(blob.count), Self.sqliteTransient)
                }
            }

            if let metadata = chunk.metadata,
               let mdData = try? JSONSerialization.data(withJSONObject: metadata),
               let mdString = String(data: mdData, encoding: .utf8)
            {
                sqlite3_bind_text(stmt, 6, mdString, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_double(stmt, 7, now)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let err = sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown"
                logger.error("VectorStore insert failed: \(err, privacy: .public)")
            }
        }
    }

    /// Deletes all chunks for `(namespace, itemID)`. No-op if none exist.
    func delete(namespace: String, itemID: String) {
        guard let db else { return }
        let sql = "DELETE FROM vectors WHERE namespace = ? AND item_id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, namespace, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, itemID, -1, Self.sqliteTransient)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("VectorStore.delete failed for \(namespace, privacy: .public)")
            }
        }
        sqlite3_finalize(stmt)
    }

    /// Removes every row in the namespace. Useful for full re-index or testing.
    func clear(namespace: String) {
        guard let db else { return }
        let sql = "DELETE FROM vectors WHERE namespace = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, namespace, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Number of chunks indexed in `namespace`.
    func count(namespace: String) -> Int {
        guard let db else { return 0 }
        let sql = "SELECT COUNT(*) FROM vectors WHERE namespace = ?"
        var stmt: OpaquePointer?
        var total = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, namespace, -1, Self.sqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return total
    }

    /// Top-K cosine search across `namespace`. Returns hits sorted descending by score.
    /// Brute-force; good for the chunk volumes we expect (10K-50K).
    func search(
        namespace: String,
        queryEmbedding: [Float],
        limit: Int = 5,
        minScore: Float = -1
    ) -> [VectorHit] {
        guard let db, !queryEmbedding.isEmpty, limit > 0 else { return [] }

        let sql = """
        SELECT item_id, chunk_idx, chunk_text, embedding, metadata
        FROM vectors WHERE namespace = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("VectorStore.search prepare failed")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, namespace, -1, Self.sqliteTransient)

        // Min-heap of size `limit`, keyed by score ascending — pops the smallest when full.
        // Implemented via an array kept sorted descending; we trim to `limit` after each insert.
        var topK: [VectorHit] = []
        topK.reserveCapacity(limit + 1)

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 3) else { continue }
            let blobLen = Int(sqlite3_column_bytes(stmt, 3))
            let candidate = Self.dataToFloats(blob: blob, byteCount: blobLen)
            guard candidate.count == queryEmbedding.count else { continue }

            let score = EmbeddingService.cosine(queryEmbedding, candidate)
            if score < minScore {
                continue
            }
            // Skip if already worse than the current K-th best.
            if topK.count >= limit, let last = topK.last, score <= last.score {
                continue
            }

            let itemID = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let chunkIdx = Int(sqlite3_column_int(stmt, 1))
            let chunkText = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""

            var metadata: [String: String]?
            if let mdPtr = sqlite3_column_text(stmt, 4) {
                let mdString = String(cString: mdPtr)
                if let mdData = mdString.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: mdData) as? [String: String]
                {
                    metadata = parsed
                }
            }

            let hit = VectorHit(
                namespace: namespace,
                itemID: itemID,
                chunkIdx: chunkIdx,
                chunkText: chunkText,
                metadata: metadata,
                score: score
            )

            // Insert keeping descending sort, then trim to `limit`.
            let insertAt = topK.firstIndex(where: { $0.score < score }) ?? topK.count
            topK.insert(hit, at: insertAt)
            if topK.count > limit {
                topK.removeLast()
            }
        }
        return topK
    }

    // MARK: - Encoding Helpers

    /// SQLITE_TRANSIENT signals SQLite to copy the bound buffer; required because
    /// our Swift strings/blobs are temporary. Without this, SQLite reads garbage.
    private static let sqliteTransient = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    private static func floatsToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { buf in
            Data(buffer: buf)
        }
    }

    private static func dataToFloats(blob: UnsafeRawPointer, byteCount: Int) -> [Float] {
        // Reject misaligned blobs. A non-multiple-of-4 length signals corruption
        // in vectors.sqlite (e.g. truncated row, downgrade from a future schema).
        // Returning [] is a no-op upstream — the row contributes 0 hits to
        // semantic search, which is safer than silently mis-decoding the vector.
        guard byteCount > 0, byteCount % MemoryLayout<Float>.size == 0 else {
            return []
        }
        let count = byteCount / MemoryLayout<Float>.size
        let floats = UnsafeBufferPointer(
            start: blob.assumingMemoryBound(to: Float.self),
            count: count
        )
        return Array(floats)
    }
}
