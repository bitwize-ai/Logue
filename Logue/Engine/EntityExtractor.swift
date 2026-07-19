import Foundation
import os.log

/// Phase E: Extracts named entities and relationships from text chunks using the
/// local LLM, then stores them in `VectorStore` for graph-enhanced retrieval.
///
/// Extraction is **gated** behind the "Build Knowledge Graph" UserDefaults flag
/// (`AppConstants.Keys.graphEnabled`) — off by default since it uses inference.
/// `SemanticIndex` calls `extractAndStore(chunks:namespace:itemID:)` as a
/// post-index hook after every successful meeting or document index run.
actor EntityExtractor {
    static let shared = EntityExtractor()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "EntityExtractor")
    private var schemaReady = false

    private static let settingsKey = "graph.buildKnowledgeGraph"
    private static let batchSize = 5 // chunks per LLM call
    private static let maxCharsPerBatch = 4000

    private init() {}

    // MARK: - Public API

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.settingsKey)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.settingsKey)
    }

    /// Entry point called after a meeting or document is indexed.
    /// No-ops when the "Build Knowledge Graph" setting is off.
    func extractAndStore(chunks: [String], namespace: String, itemID: String) async {
        guard isEnabled else { return }
        await ensureSchema()

        let batches = stride(from: 0, to: chunks.count, by: Self.batchSize).map {
            Array(chunks[$0 ..< min($0 + Self.batchSize, chunks.count)])
        }

        for batch in batches {
            guard !Task.isCancelled else { break }
            do {
                let response = try await extractEntities(from: batch, itemID: itemID)
                await persistResponse(response, namespace: namespace, itemID: itemID)
            } catch {
                logger.warning(
                    "Entity extraction batch failed for \(itemID, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Schema

    private func ensureSchema() async {
        guard !schemaReady else { return }
        await VectorStore.shared.createGraphSchema()
        schemaReady = true
    }

    // MARK: - LLM extraction

    private func extractEntities(from chunks: [String], itemID: String) async throws -> EntityExtractionResponse {
        let combined = chunks
            .map { $0.prefix(Self.maxCharsPerBatch / Self.batchSize) }
            .joined(separator: "\n---\n")
            .prefix(Self.maxCharsPerBatch)

        let system = """
        You are an entity extractor. Given text, extract:
        1. Named entities (people, organizations, topics, technologies, locations).
        2. Relationships between those entities.
        Output ONLY valid JSON in this exact schema — no prose:
        {
          "entities": [{"name": "string", "type": "person|organization|topic|technology|location|other"}],
          "relationships": [{"source": "string", "target": "string", "relationship": "short verb phrase"}]
        }
        Keep names concise. Omit generic nouns ("meeting", "document", "issue").
        Output at most 15 entities and 10 relationships.
        """

        let user = "<text>\n\(combined)\n</text>"
        let raw = try await LLMEngine.shared.complete(system: system, prompt: user, maxTokens: 512)
        return try parseExtractionResponse(raw)
    }

    private func parseExtractionResponse(_ raw: String) throws -> EntityExtractionResponse {
        // Strip markdown fences if present.
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ExtractionError.invalidJSON("empty response")
        }

        do {
            return try JSONDecoder().decode(EntityExtractionResponse.self, from: data)
        } catch {
            logger.error("Entity JSON decode failed: \(error.localizedDescription, privacy: .public) — raw: \(cleaned.prefix(200), privacy: .public)")
            throw ExtractionError.invalidJSON(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func persistResponse(
        _ response: EntityExtractionResponse,
        namespace: String,
        itemID: String
    ) async {
        for record in response.entities {
            guard !record.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let entity = GraphEntity(name: record.name, type: record.type, namespace: namespace, itemID: itemID)
            await VectorStore.shared.upsertEntity(entity)
        }

        let entityNames = Set(response.entities.map { $0.name.lowercased() })
        for record in response.relationships {
            let src = record.source.lowercased()
            let tgt = record.target.lowercased()
            guard entityNames.contains(src) || entityNames.contains(tgt) else { continue }
            let rel = GraphRelationship(
                sourceName: src,
                targetName: tgt,
                relationship: String(record.relationship.prefix(80)),
                sourceItemID: itemID
            )
            await VectorStore.shared.upsertRelationship(rel)
        }
    }

    // MARK: - Error

    enum ExtractionError: Error {
        case invalidJSON(String)
    }
}
