import Foundation
import os.log

/// Cross-conversation memory: auto-extracted personal facts about the user, recalled
/// via cosine similarity into the agent's system prompt.
///
/// Pipeline:
/// 1. After each user message, `rememberIfNeeded(_:messageID:)` runs the extraction
///    prompt on `LLMEngine.complete()` (gate-serialized — no second model needed).
/// 2. Validates the response (must start with "The user", 15–400 chars, not "nil").
/// 3. Embeds the validated text via `EmbeddingService` and writes to `VectorStore`
///    under namespace `"memory"`.
/// 4. Before each agent reasoning round, `recall(_:k:)` embeds the query and pulls
///    the top-K cosine matches above threshold (0.6, mirroring Sidekick).
///
/// Persistence: the metadata list (id, text, dates) is encrypted JSON at
/// `~/Library/Application Support/<bundleID>/memories.json`. Embeddings live in
/// `vectors.sqlite` (managed by `VectorStore`).
actor MemoryStore {
    static let shared = MemoryStore()

    /// Namespace inside `VectorStore` where memory embeddings live.
    static let namespace = "memory"

    /// In-memory cache of every memory. Loaded on first access; kept in sync with
    /// disk + the vector store.
    private var memories: [UserMemory] = []
    private var isLoaded = false

    /// Cosine similarity threshold for recall — below this, results are discarded
    /// as not-relevant. Matches Sidekick's `MemoryConstants.recallThreshold`.
    static let recallThreshold: Float = 0.6

    /// Length bounds for the extraction prompt's response. Anything outside this
    /// window is treated as a model error and discarded silently.
    private static let minLen = 15
    private static let maxLen = 400

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MemoryStore")

    private static var storageURL: URL {
        URL.applicationSupportDirectory
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "memories.json")
    }

    private init() {}

    // MARK: - Loading / Persisting

    private func ensureLoaded() async {
        // Set the flag BEFORE the await — actor reentrancy means a second
        // caller can land here between our suspension points. With the flag
        // flipped first, that second caller short-circuits at the guard and
        // we don't load twice (the second load would clobber the in-memory
        // list with the same content but is wasted work).
        guard !isLoaded else { return }
        isLoaded = true
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            let data = try Data(contentsOf: url)
            do {
                let list = try EncryptionManager.decryptCodable([UserMemory].self, from: data)
                memories = list
            } catch {
                // Try unencrypted fallback for dev/legacy data — same pattern as AgentConversationStore.
                do {
                    let list = try JSONDecoder().decode([UserMemory].self, from: data)
                    memories = list
                } catch {
                    logger.error("Failed to decode memories.json: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.error("Failed to read memories.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveToDisk() {
        let snapshot = memories
        Task.detached(priority: .utility) {
            do {
                let dir = Self.storageURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try EncryptionManager.encryptCodable(snapshot)
                try data.write(to: Self.storageURL, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "MemoryStore")
                    .error("Failed to save memories: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Extraction

    /// Best-effort extraction. Runs the worker prompt on `LLMEngine.complete()`,
    /// validates the response, embeds it, and persists. Errors are logged and
    /// swallowed — memory is a "nice to have" feature; failures must not break
    /// the parent agent loop.
    func rememberIfNeeded(userMessage: String, messageID: UUID? = nil) async {
        await ensureLoaded()

        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Validate context window. Memory extraction has tiny output (one line) so
        // we reserve very little for response.
        let maxChars = LLMEngine.maxInputChars(reservedTokens: 64)
        let safeMessage = String(trimmed.prefix(maxChars))

        let extracted: String
        do {
            extracted = try await LLMEngine.shared.complete(
                system: PromptRegistry.Memory.extractionSystem.content,
                prompt: PromptRegistry.Memory.extractionPrompt(message: safeMessage),
                temperature: 0.0,
                maxTokens: 96
            )
        } catch {
            logger.debug("Memory extraction failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let validated = Self.validateExtraction(extracted) else { return }

        // De-dupe near-identical memories before paying for an embedding round-trip.
        // Cheap normalized check — anything more nuanced relies on the embedding
        // similarity test below.
        if memories.contains(where: { Self.normalize($0.text) == Self.normalize(validated) }) {
            return
        }

        let embedding: [Float]
        do {
            embedding = try await EmbeddingService.shared.embed(validated)
        } catch {
            logger.error("Memory embedding failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Embedding-based de-dupe — if a stored memory is >0.9 similar, treat as duplicate.
        let existingHits = await VectorStore.shared.search(
            namespace: Self.namespace,
            queryEmbedding: embedding,
            limit: 1,
            minScore: 0.9
        )
        if !existingHits.isEmpty {
            return
        }

        let memory = UserMemory(text: validated, sourceMessageID: messageID)
        memories.append(memory)

        await VectorStore.shared.upsert(
            namespace: Self.namespace,
            itemID: memory.id.uuidString,
            chunks: [
                VectorChunk(
                    chunkIdx: -1,
                    chunkText: memory.text,
                    embedding: embedding,
                    metadata: [
                        "createdAt": ISO8601DateFormatter().string(from: memory.createdAt),
                    ]
                ),
            ]
        )
        saveToDisk()
        logger.info("Remembered: \(validated, privacy: .private)")
    }

    /// Returns up to `k` memory texts whose embedding is closest to `query`.
    /// Falls back to an empty list (rather than throwing) so callers can treat
    /// memory recall as best-effort.
    func recall(query: String, k: Int = 5) async -> [String] {
        await ensureLoaded()
        guard !memories.isEmpty else { return [] }

        let embedding: [Float]
        do {
            embedding = try await EmbeddingService.shared.embed(query)
        } catch {
            logger.debug("Recall embedding failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let hits = await VectorStore.shared.search(
            namespace: Self.namespace,
            queryEmbedding: embedding,
            limit: k,
            minScore: Self.recallThreshold
        )
        return hits.map(\.chunkText)
    }

    // MARK: - User-curated CRUD (for MemoryListView)

    func allMemories() async -> [UserMemory] {
        await ensureLoaded()
        return memories.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Replaces the body of a memory (re-embeds + re-upserts so recall stays aligned).
    func updateMemory(id: UUID, newText: String) async {
        await ensureLoaded()
        guard let idx = memories.firstIndex(where: { $0.id == id }),
              let validated = Self.validateExtraction(newText, allowAnyVerb: true)
        else { return }

        let embedding: [Float]
        do {
            embedding = try await EmbeddingService.shared.embed(validated)
        } catch {
            logger.error("Update embedding failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        memories[idx].text = validated
        memories[idx].modifiedAt = .now

        await VectorStore.shared.upsert(
            namespace: Self.namespace,
            itemID: id.uuidString,
            chunks: [
                VectorChunk(chunkIdx: -1, chunkText: validated, embedding: embedding, metadata: nil),
            ]
        )
        saveToDisk()
    }

    func deleteMemory(id: UUID) async {
        await ensureLoaded()
        memories.removeAll { $0.id == id }
        await VectorStore.shared.delete(namespace: Self.namespace, itemID: id.uuidString)
        saveToDisk()
    }

    func clearAll() async {
        await ensureLoaded()
        memories.removeAll()
        await VectorStore.shared.clear(namespace: Self.namespace)
        saveToDisk()
    }

    // MARK: - Validation

    /// Validates the LLM extraction response. Must start with "The user", be within
    /// length bounds, and not be the literal "nil" sentinel. Returns the cleaned
    /// text or nil to discard.
    ///
    /// `allowAnyVerb` relaxes the "starts with The user" rule so user-edited memories
    /// can take any form (e.g. "I prefer...", direct facts).
    private static func validateExtraction(_ raw: String, allowAnyVerb: Bool = false) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard !cleaned.isEmpty else { return nil }
        guard cleaned.lowercased() != "nil" else { return nil }
        guard cleaned.count >= minLen, cleaned.count <= maxLen else { return nil }

        if !allowAnyVerb {
            // Lowercase compare — model formatting can vary.
            let lower = cleaned.lowercased()
            guard lower.hasPrefix("the user ") else { return nil }
        }
        return cleaned
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isPunctuation }
    }
}
