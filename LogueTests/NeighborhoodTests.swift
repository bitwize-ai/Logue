import Foundation
@testable import Logue
import Testing

/// The grouped graph neighbourhood around one item.
@Suite("Neighborhood")
struct NeighborhoodTests {
    private let alphaID = UUID()
    private let betaID = UUID()
    private let gammaID = UUID()

    private func entry(
        _ id: UUID,
        _ title: String,
        body: String = "",
        relationships: [RelationshipKind: [String]] = [:]
    ) -> LinkIndex.Entry {
        LinkIndex.Entry(
            id: id, title: title, body: body,
            kind: .document, relationships: relationships
        )
    }

    @Test("The source item is identified and never appears in its own groups")
    func sourceExcludedFromGroups() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]"),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        #expect(neighborhood.sourceTitle == "Alpha")
        #expect(neighborhood.groups.allSatisfy { !$0.itemIDs.contains(alphaID) })
    }

    @Test("Outgoing body links form a group")
    func outgoingGroup() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]"),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        let group = neighborhood.groups.first { $0.title == "Links to" }
        #expect(group?.itemIDs == [betaID])
    }

    @Test("Backlinks form their own group")
    func backlinkGroup() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]"),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: betaID)

        let group = neighborhood.groups.first { $0.title == "Linked from" }
        #expect(group?.itemIDs == [alphaID])
    }

    @Test("Each relationship kind forms its own group")
    func relationshipGroups() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        #expect(neighborhood.groups.contains { $0.title == RelationshipKind.belongsTo.label })
    }

    @Test("A computed inverse relationship appears as a group on the target")
    func inverseRelationshipGroup() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: betaID)

        let group = neighborhood.groups.first { $0.title == RelationshipKind.has.label }
        #expect(group?.itemIDs == [alphaID])
    }

    @Test("Empty groups are omitted")
    func emptyGroupsOmitted() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha")])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        #expect(neighborhood.groups.isEmpty)
        #expect(neighborhood.isEmpty)
    }

    @Test("An item may appear in more than one group when several relations are true")
    func overlappingGroupsPreserved() {
        // Alpha both links to Beta in its body and declares it related.
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]", relationships: [.relatedTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        let containing = neighborhood.groups.filter { $0.itemIDs.contains(betaID) }
        #expect(containing.count == 2)
    }

    @Test("A source with no entry in the index yields an empty neighbourhood")
    func unknownSource() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha")])
        let neighborhood = Neighborhood(index: index, sourceID: UUID())

        #expect(neighborhood.isEmpty)
        #expect(neighborhood.sourceTitle == nil)
    }

    @Test("Total neighbour count counts distinct items, not group entries")
    func distinctNeighbourCount() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]", relationships: [.relatedTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        #expect(neighborhood.distinctNeighbourCount == 1)
    }

    @Test("Groups carry the kind of each item for display")
    func groupsExposeKinds() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", body: "[[Beta]]"),
            LinkIndex.Entry(id: betaID, title: "Beta", body: "", kind: .meeting),
        ])
        let neighborhood = Neighborhood(index: index, sourceID: alphaID)

        #expect(index.kind(of: betaID) == .meeting)
        #expect(neighborhood.groups.first?.itemIDs == [betaID])
    }

    @Test("Groups appear in a stable order across rebuilds")
    func stableGroupOrder() {
        let entries = [
            entry(alphaID, "Alpha", body: "[[Beta]]", relationships: [.belongsTo: ["Gamma"]]),
            entry(betaID, "Beta"),
            entry(gammaID, "Gamma"),
        ]
        let first = Neighborhood(index: LinkIndex(entries: entries), sourceID: alphaID)
        let second = Neighborhood(index: LinkIndex(entries: entries), sourceID: alphaID)

        #expect(first.groups.map(\.title) == second.groups.map(\.title))
    }
}
