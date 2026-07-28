import Foundation

/// The graph neighbourhood around one item: every other item connected to it,
/// grouped by how it is connected.
///
/// Deliberately preserves overlap. If a note both links to another in its body and
/// declares it related, it appears in both groups — collapsing that would hide
/// genuine graph structure, which is the opposite of what a graph view is for.
struct Neighborhood: Sendable {
    /// One reason-for-connection, with the items connected that way.
    struct Group: Identifiable, Sendable {
        let id: String
        let title: String
        let symbolName: String
        let itemIDs: [UUID]
    }

    /// Title of the item this neighbourhood is centred on; `nil` when the source is
    /// not in the index.
    let sourceTitle: String?
    /// Non-empty groups, in a stable order: body links first, then relationships.
    let groups: [Group]

    init(index: LinkIndex, sourceID: UUID) {
        sourceTitle = index.title(of: sourceID)

        var built: [Group] = []

        func addGroup(id: String, title: String, symbol: String, ids: [UUID]) {
            let filtered = ids.filter { $0 != sourceID }
            guard !filtered.isEmpty else { return }
            built.append(Group(id: id, title: title, symbolName: symbol, itemIDs: filtered))
        }

        addGroup(
            id: "outgoing", title: "Links to",
            symbol: "arrow.up.right", ids: index.outgoing(from: sourceID)
        )
        addGroup(
            id: "backlinks", title: "Linked from",
            symbol: "arrow.down.left", ids: index.backlinks(to: sourceID)
        )

        // `allCases` order gives a stable group order across rebuilds.
        for kind in RelationshipKind.allCases {
            addGroup(
                id: kind.key, title: kind.label,
                symbol: kind.symbolName, ids: index.related(from: sourceID, kind: kind)
            )
        }

        groups = built
    }

    var isEmpty: Bool {
        groups.isEmpty
    }

    /// How many distinct items are connected, counting an item once even when it
    /// appears in several groups.
    var distinctNeighbourCount: Int {
        Set(groups.flatMap(\.itemIDs)).count
    }
}
