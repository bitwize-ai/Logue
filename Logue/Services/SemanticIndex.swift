import CryptoKit
import Foundation
import os.log

/// Coordinates chunking, embedding, and vector-store writes for meetings and documents.
/// Provides semantic retrieval as a complement to `MeetingMemoryIndex`'s FTS5 keyword
/// search — the agent's `semantic_search_*` tools query this index.
///
/// Pipeline (per item):
/// 1. Build "source text" from the item (transcript for meetings, body for documents).
/// 2. Hash the source text — skip if unchanged since last indexing.
/// 3. Chunk on sentence boundaries, ~1024 chars/chunk, capped at `maxChunksPerItem`.
/// 4. Embed each chunk via `EmbeddingService`.
/// 5. Upsert into `VectorStore` under namespace `"meeting"` or `"document"`.
///
/// All work happens on the actor's executor — never on @MainActor. Indexing is
/// fire-and-forget from the perspective of the calling stores; failures are logged
/// but never block the parent save.
actor SemanticIndex {
    static let shared = SemanticIndex()

    static let meetingNamespace = "meeting"
    static let documentNamespace = "document"

    /// Max chunks indexed per item. Long meetings still keep the FTS5 keyword path
    /// for the tail; semantic recall covers the leading 200 chunks.
    private static let maxChunksPerItem = 200
    /// Target chunk length in characters. Sentences exceeding this are split mid-sentence.
    private static let targetChunkChars = 1024
    /// Skip extremely short items — embedding 5-char strings produces noise.
    private static let minIndexableChars = 32

    /// In-memory hash cache keyed by `<namespace>:<itemID>`. Populated lazily from disk.
    private var contentHashes: [String: String] = [:]
    private var hashesLoaded = false

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SemanticIndex")

    private static var hashStorageURL: URL {
        URL.applicationSupportDirectory
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Vectors", directoryHint: .isDirectory)
            .appending(path: "semantic_index_meta.json")
    }

    private init() {}

    // MARK: - Public API

    /// Index a meeting if its transcript changed since the last index. No-op on
    /// trashed meetings (they're removed from the index instead).
    func indexMeeting(_ meeting: MeetingNote) async {
        await ensureHashesLoaded()

        let id = meeting.id.uuidString
        guard !meeting.isTrashed else {
            await removeMeeting(id: meeting.id)
            return
        }

        let sourceText = Self.buildMeetingSourceText(meeting)
        guard sourceText.count >= Self.minIndexableChars else {
            await removeMeeting(id: meeting.id)
            return
        }

        let hash = Self.contentHash(of: sourceText)
        let cacheKey = "\(Self.meetingNamespace):\(id)"
        if contentHashes[cacheKey] == hash {
            return
        }

        let metadata: [String: String] = [
            "title": meeting.title,
            "date": ISO8601DateFormatter().string(from: meeting.createdAt),
            "kind": "meeting",
        ]
        await indexItem(
            namespace: Self.meetingNamespace,
            itemID: id,
            sourceText: sourceText,
            metadata: metadata
        )
        contentHashes[cacheKey] = hash
        saveHashes()
    }

    /// Index a document if its body changed since the last index.
    func indexDocument(_ document: WritingDocument) async {
        await ensureHashesLoaded()

        let id = document.id.uuidString
        guard !document.isTrashed else {
            await removeDocument(id: document.id)
            return
        }

        let sourceText = Self.buildDocumentSourceText(document)
        guard sourceText.count >= Self.minIndexableChars else {
            await removeDocument(id: document.id)
            return
        }

        let hash = Self.contentHash(of: sourceText)
        let cacheKey = "\(Self.documentNamespace):\(id)"
        if contentHashes[cacheKey] == hash {
            return
        }

        var metadata: [String: String] = [
            "title": document.title,
            "modifiedAt": ISO8601DateFormatter().string(from: document.modifiedAt),
            "kind": "document",
        ]
        if let spaceID = document.spaceID {
            metadata["spaceID"] = spaceID.uuidString
        }
        await indexItem(
            namespace: Self.documentNamespace,
            itemID: id,
            sourceText: sourceText,
            metadata: metadata
        )
        contentHashes[cacheKey] = hash
        saveHashes()
    }

    /// Removes all chunks for a meeting from the vector store + hash cache.
    func removeMeeting(id: UUID) async {
        await VectorStore.shared.delete(namespace: Self.meetingNamespace, itemID: id.uuidString)
        contentHashes.removeValue(forKey: "\(Self.meetingNamespace):\(id.uuidString)")
        saveHashes()
    }

    /// Removes all chunks for a document.
    func removeDocument(id: UUID) async {
        await VectorStore.shared.delete(namespace: Self.documentNamespace, itemID: id.uuidString)
        contentHashes.removeValue(forKey: "\(Self.documentNamespace):\(id.uuidString)")
        saveHashes()
    }

    /// Wipes both namespaces and the hash cache. Used by `clearAllData`.
    func clearAll() async {
        await VectorStore.shared.clear(namespace: Self.meetingNamespace)
        await VectorStore.shared.clear(namespace: Self.documentNamespace)
        contentHashes.removeAll()
        saveHashes()
    }

    /// Bulk re-index. Called after `loadFromDiskAsync` so the agent has semantic
    /// retrieval available as soon as data is loaded. Hash check inside per-item
    /// indexing makes this idempotent — only changed items pay the embedding cost.
    func rebuild(meetings: [MeetingNote], documents: [WritingDocument]) async {
        await ensureHashesLoaded()
        for meeting in meetings {
            await indexMeeting(meeting)
        }
        for document in documents {
            await indexDocument(document)
        }
    }

    /// Returns top-K hits across the meeting namespace. Public surface for
    /// `SemanticSearchMeetingsTool`.
    func searchMeetings(query: String, limit: Int = 5) async -> [VectorHit] {
        await search(namespace: Self.meetingNamespace, query: query, limit: limit)
    }

    /// Returns top-K hits across the document namespace.
    func searchDocuments(query: String, limit: Int = 5) async -> [VectorHit] {
        await search(namespace: Self.documentNamespace, query: query, limit: limit)
    }

    // MARK: - Indexing core

    private func indexItem(
        namespace: String,
        itemID: String,
        sourceText: String,
        metadata: [String: String]
    ) async {
        let chunks = Self.chunkText(sourceText)
        guard !chunks.isEmpty else { return }

        var vectorChunks: [VectorChunk] = []
        vectorChunks.reserveCapacity(chunks.count)

        for (idx, chunk) in chunks.enumerated() {
            let embedding: [Float]
            do {
                embedding = try await EmbeddingService.shared.embed(chunk)
            } catch {
                logger.error("Embedding failed for \(namespace, privacy: .public)/chunk \(idx): \(error.localizedDescription, privacy: .public)")
                continue
            }
            vectorChunks.append(
                VectorChunk(
                    chunkIdx: idx,
                    chunkText: chunk,
                    embedding: embedding,
                    metadata: metadata
                )
            )
        }

        guard !vectorChunks.isEmpty else { return }
        await VectorStore.shared.upsert(
            namespace: namespace,
            itemID: itemID,
            chunks: vectorChunks
        )

        // Phase E: post-index entity extraction (gated; no-ops when disabled).
        let rawChunks = chunks
        Task.detached(priority: .background) {
            await EntityExtractor.shared.extractAndStore(
                chunks: rawChunks,
                namespace: namespace,
                itemID: itemID
            )
        }
    }

    private func search(namespace: String, query: String, limit: Int) async -> [VectorHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let embedding: [Float]
        do {
            embedding = try await EmbeddingService.shared.embed(trimmed)
        } catch {
            logger.debug("Search embedding failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return await VectorStore.shared.search(
            namespace: namespace,
            queryEmbedding: embedding,
            limit: limit,
            // Semantic retrieval threshold — lower than memory's 0.6 because chunk-level
            // matches are less direct than memory facts.
            minScore: 0.35
        )
    }

    // MARK: - Source-text builders

    private static func buildMeetingSourceText(_ meeting: MeetingNote) -> String {
        // Prefer the spoken transcript; fall back to summary if no segments.
        let transcript = meeting.segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript
        }
        if let summary = meeting.summary, !summary.isEmpty {
            return summary
        }
        return ""
    }

    private static func buildDocumentSourceText(_ document: WritingDocument) -> String {
        // Title prefix helps semantic search pick up titled-only documents.
        if document.body.isEmpty {
            return document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(document.title)\n\n\(document.body)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chunking

    /// Sentence-aware chunker. Walks sentence ranges, accumulating into chunks until
    /// `targetChunkChars` is reached, then starts a new chunk. Sentences that exceed
    /// the budget on their own get hard-split mid-sentence so we don't drop content.
    nonisolated static func chunkText(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex ..< text.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            if let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                sentences.append(trimmed)
            }
        }
        if sentences.isEmpty {
            sentences = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            // Sentence alone exceeds target — hard-split it before continuing.
            if sentence.count > targetChunkChars {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                    if chunks.count >= maxChunksPerItem {
                        return chunks
                    }
                }
                var startIdx = sentence.startIndex
                while startIdx < sentence.endIndex {
                    let endIdx = sentence.index(
                        startIdx,
                        offsetBy: targetChunkChars,
                        limitedBy: sentence.endIndex
                    ) ?? sentence.endIndex
                    chunks.append(String(sentence[startIdx ..< endIdx]))
                    if chunks.count >= maxChunksPerItem {
                        return chunks
                    }
                    startIdx = endIdx
                }
                continue
            }

            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= targetChunkChars {
                current += " " + sentence
            } else {
                chunks.append(current)
                if chunks.count >= maxChunksPerItem {
                    return chunks
                }
                current = sentence
            }
        }
        if !current.isEmpty, chunks.count < maxChunksPerItem {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Hash cache persistence

    private func ensureHashesLoaded() async {
        guard !hashesLoaded else { return }
        hashesLoaded = true
        let url = Self.hashStorageURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            let data = try Data(contentsOf: url)
            let map = try JSONDecoder().decode([String: String].self, from: data)
            contentHashes = map
        } catch {
            // Cache is corrupt (e.g. truncated, schema changed). Wipe and let
            // the indexer rebuild — better to pay the re-embed cost than to
            // run forever with a broken stale cache.
            logger.warning("semantic_index_meta.json corrupt, rebuilding: \(error.localizedDescription, privacy: .public)")
            contentHashes = [:]
            saveHashes()
        }
    }

    private func saveHashes() {
        let snapshot = contentHashes
        Task.detached(priority: .utility) {
            do {
                let dir = Self.hashStorageURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: Self.hashStorageURL, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "SemanticIndex")
                    .error("Failed to persist hash cache: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func contentHash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
