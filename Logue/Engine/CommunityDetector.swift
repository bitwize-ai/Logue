import Foundation
import os.log

/// Phase E: Detects communities in the entity graph using union-find connected
/// components, then generates LLM titles + summaries for each cluster.
///
/// Triggered from `SemanticIndex` after an entity-extraction run completes.
/// Stores results in `VectorStore` via `upsertCommunity(_:)`.
actor CommunityDetector {
    static let shared = CommunityDetector()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "CommunityDetector")

    /// Minimum cluster size to warrant an LLM summary call.
    private static let minClusterSize = 3
    /// Maximum entities summarized in one LLM call.
    private static let maxEntitiesInPrompt = 20

    private init() {}

    // MARK: - Public API

    /// Reads all entities + relationships from VectorStore, runs connected-components,
    /// generates LLM summaries for clusters ≥ `minClusterSize`, and persists them.
    /// Returns a human-readable summary suitable for the Settings UI.
    @discardableResult
    func rebuildCommunities() async -> String {
        let entities = await VectorStore.shared.allGraphEntities()
        let relationships = await VectorStore.shared.allGraphRelationships()
        guard !entities.isEmpty else {
            return "No entities yet — index a meeting or document first."
        }

        let clusters = connectedComponents(entities: entities, relationships: relationships)
        let large = clusters.filter { $0.count >= Self.minClusterSize }
        var built = 0

        for cluster in large {
            guard !Task.isCancelled else { break }
            do {
                let community = try await summarize(cluster: cluster)
                await VectorStore.shared.upsertCommunity(community)
                built += 1
                logger.info(
                    "Community stored: \(community.title, privacy: .public) (\(cluster.count) entities)"
                )
            } catch {
                logger.warning(
                    "Community summary failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return "\(built) communities built from \(entities.count) entities"
    }

    // MARK: - Union-Find

    /// Returns clusters of entity names, each cluster being a connected component.
    private func connectedComponents(
        entities: [GraphEntity],
        relationships: [GraphRelationship]
    ) -> [[String]] {
        var parent: [String: String] = [:]
        for entity in entities {
            parent[entity.name] = entity.name
        }

        func find(_ name: String) -> String {
            var root = name
            while parent[root] != root {
                root = parent[root] ?? root
            }
            // Path compression
            var current = name
            while current != root {
                let next = parent[current] ?? root
                parent[current] = root
                current = next
            }
            return root
        }

        func union(_ nameA: String, _ nameB: String) {
            let rootA = find(nameA)
            let rootB = find(nameB)
            if rootA != rootB {
                parent[rootB] = rootA
            }
        }

        for rel in relationships {
            guard parent[rel.sourceName] != nil, parent[rel.targetName] != nil else { continue }
            union(rel.sourceName, rel.targetName)
        }

        var groups: [String: [String]] = [:]
        for entity in entities {
            let root = find(entity.name)
            groups[root, default: []].append(entity.name)
        }
        return Array(groups.values)
    }

    // MARK: - LLM summary

    private func summarize(cluster: [String]) async throws -> GraphCommunity {
        let truncated = Array(cluster.prefix(Self.maxEntitiesInPrompt))
        let entityList = truncated.joined(separator: ", ")

        let system = "You are a knowledge graph analyst. Given a list of related entities,"
            + " produce a short title and a 1–2 sentence summary describing what they have in common."
            + " Output JSON only: {\"title\": \"...\", \"summary\": \"...\"}"
        let user = "<entities>\n\(entityList)\n</entities>"

        let raw = try await LLMEngine.shared.complete(system: system, prompt: user, maxTokens: 200)
        let (title, summary) = parseSummary(raw)

        let communityID = truncated.sorted().joined(separator: "|")
        return GraphCommunity(
            id: communityID,
            level: 1,
            title: title,
            summary: summary,
            memberNames: truncated
        )
    }

    private func parseSummary(_ raw: String) -> (title: String, summary: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONDecoder().decode(CommunitySummaryResponse.self, from: data)
        else {
            // Fallback: use first 60 chars as title.
            let fallback = String(cleaned.prefix(60))
            return (fallback.isEmpty ? "Cluster" : fallback, "")
        }
        return (json.title, json.summary)
    }

    // MARK: - JSON model

    private struct CommunitySummaryResponse: Codable {
        let title: String
        let summary: String
    }
}
