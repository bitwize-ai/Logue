import Foundation
import os.log

// MARK: - VectorStore.search convenience (accepts String query)

private extension VectorStore {
    func search(namespace: String, query: String, topK: Int) async -> [VectorHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let embedding: [Float]
        do {
            embedding = try await EmbeddingService.shared.embed(trimmed)
        } catch {
            return []
        }
        return await search(namespace: namespace, queryEmbedding: embedding, limit: topK, minScore: 0.30)
    }
}

/// Phase E: Graph-enhanced semantic retrieval. Wraps `VectorStore.search` with a
/// 1-hop entity-graph expansion pass that pulls in additional contextually related
/// chunks and applies community-summary context to the final result set.
///
/// Usage:
/// ```swift
/// let hits = await GraphRetriever.shared.search(
///     query: "who worked on the infra project?",
///     namespaces: ["meeting", "document"],
///     topK: 8
/// )
/// ```
actor GraphRetriever {
    static let shared = GraphRetriever()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "GraphRetriever")

    /// Score boost applied to chunks that share entities with the seed result set.
    private static let entityBoost: Float = 0.10
    /// Score boost for chunks whose source item appears in a community summary match.
    private static let communityBoost: Float = 0.05
    /// Seed vector search K (before graph expansion).
    private static let seedK = 10

    private init() {}

    // MARK: - Public API

    /// Graph-enhanced search. Falls back to plain vector search when the graph
    /// has no entities (e.g. first run before entity extraction completes).
    func search(query: String, namespaces: [String], topK: Int) async -> [VectorHit] {
        var allHits: [VectorHit] = []

        // Step 1: Seed vector search across all requested namespaces.
        for ns in namespaces {
            let hits = await VectorStore.shared.search(namespace: ns, query: query, topK: Self.seedK)
            allHits.append(contentsOf: hits)
        }

        guard !allHits.isEmpty else { return [] }

        // Step 2: Collect seed item IDs and find their graph entities.
        let seedItemIDs = Set(allHits.map(\.itemID))
        let seedEntityNames = await VectorStore.shared.entityNames(inItemIDs: seedItemIDs)

        // Without graph data, just return sorted seeds.
        guard !seedEntityNames.isEmpty else {
            return Array(allHits.sorted { $0.score > $1.score }.prefix(topK))
        }

        // Step 3: 1-hop neighbor expansion — get adjacent entity names.
        let neighborNames = await VectorStore.shared.neighbors(ofEntities: seedEntityNames)

        // Step 4: Fetch item IDs for neighbor entities, pull their chunks.
        if !neighborNames.isEmpty {
            let neighborItemIDs = await VectorStore.shared.itemIDs(forEntityNames: neighborNames)
            let newIDs = neighborItemIDs.subtracting(seedItemIDs)
            if !newIDs.isEmpty {
                for ns in namespaces {
                    for itemID in newIDs.prefix(5) {
                        let chunks = await VectorStore.shared.fetchChunks(namespace: ns, itemID: itemID, limit: 2)
                        allHits.append(contentsOf: chunks)
                    }
                }
            }
        }

        // Step 5: Retrieve communities for seed entities and apply score boosts.
        let communities = await VectorStore.shared.communities(containingAnyOf: seedEntityNames)

        // Step 6: Deduplicate + boost + rank.
        var scored: [String: VectorHit] = [:]
        for hit in allHits {
            let key = "\(hit.namespace)/\(hit.itemID)/\(hit.chunkIdx)"
            let existing = scored[key]
            var boostedScore = hit.score

            if seedEntityNames.contains(where: { hit.itemID.contains($0) }) {
                boostedScore += Self.entityBoost
            }
            if communities.contains(where: { $0.memberNames.contains(where: { hit.itemID.contains($0) }) }) {
                boostedScore += Self.communityBoost
            }

            if existing == nil || boostedScore > (existing?.score ?? 0) {
                scored[key] = VectorHit(
                    namespace: hit.namespace,
                    itemID: hit.itemID,
                    chunkIdx: hit.chunkIdx,
                    chunkText: hit.chunkText,
                    metadata: hit.metadata,
                    score: min(1, boostedScore)
                )
            }
        }

        let results = scored.values
            .sorted { $0.score > $1.score }
            .prefix(topK)
        return Array(results)
    }
}
