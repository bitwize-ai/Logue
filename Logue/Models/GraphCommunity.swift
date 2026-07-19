import Foundation

/// A cluster of related entities produced by `CommunityDetector`.
struct GraphCommunity: Codable, Identifiable {
    let id: String // deterministic: sorted member names joined by "|"
    let level: Int // 1 = raw cluster, 2 = meta-cluster (future)
    let title: String // LLM-generated short title
    let summary: String // LLM-generated 2-sentence summary
    let memberNames: [String] // sorted, lowercased entity names

    init(id: String, level: Int, title: String, summary: String, memberNames: [String]) {
        self.id = id
        self.level = level
        self.title = title
        self.summary = summary
        self.memberNames = memberNames.map { $0.lowercased() }.sorted()
    }
}
