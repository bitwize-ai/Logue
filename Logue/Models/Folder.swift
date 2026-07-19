import Foundation

/// A persisted AI-generated insight for a space (summary, action items, decisions, etc.).
struct SpaceAIInsight: Codable, Hashable {
    var content: String
    var generatedAt: Date
    var contentSignature: String
}

/// A user-created space for organizing documents and meetings together.
/// Spaces are type-agnostic and can hold any mix of documents, meetings, and sub-spaces.
struct Space: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var createdAt: Date
    var icon: String?
    var color: String?
    var isExpanded: Bool
    var aiInsights: [String: SpaceAIInsight]?

    init(
        id: UUID = .init(),
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        icon: String? = nil,
        color: String? = nil,
        isExpanded: Bool = false,
        aiInsights: [String: SpaceAIInsight]? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.icon = icon
        self.color = color
        self.isExpanded = isExpanded
        self.aiInsights = aiInsights
    }

    /// Convenience accessor for the summary text (used in cards and search).
    var summary: String? {
        aiInsights?["summary"]?.content
    }
}
