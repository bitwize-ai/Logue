import Foundation

/// A typed relationship between two items in the library.
///
/// Relationships are declared on one side only; the other side is computed. If a
/// note says it `belongsTo` a project, the project shows that note under `has`
/// without anyone writing the reverse link by hand.
///
/// Keys use the frontmatter-style snake_case names so a future plain-markdown
/// representation can persist them unchanged.
enum RelationshipKind: String, CaseIterable, Codable, Sendable {
    case belongsTo
    case has
    case relatedTo

    /// The frontmatter key this relationship serializes as.
    var key: String {
        switch self {
        case .belongsTo: "belongs_to"
        case .has: "has"
        case .relatedTo: "related_to"
        }
    }

    init?(key: String) {
        guard let match = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = match
    }

    /// The relationship the target sees back. `relatedTo` is symmetric, so it is
    /// its own inverse.
    var inverse: RelationshipKind {
        switch self {
        case .belongsTo: .has
        case .has: .belongsTo
        case .relatedTo: .relatedTo
        }
    }

    var label: String {
        switch self {
        case .belongsTo: "Belongs to"
        case .has: "Has"
        case .relatedTo: "Related to"
        }
    }

    var symbolName: String {
        switch self {
        case .belongsTo: "arrow.up.forward.square"
        case .has: "square.stack.3d.down.right"
        case .relatedTo: "arrow.left.arrow.right"
        }
    }
}
