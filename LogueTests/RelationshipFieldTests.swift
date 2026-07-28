import Foundation
@testable import Logue
import Testing

@Suite("RelationshipFields")
struct RelationshipFieldTests {
    private let alphaID = UUID()
    private let betaID = UUID()
    private let gammaID = UUID()

    private func entry(
        _ id: UUID,
        _ title: String,
        relationships: [RelationshipKind: [String]] = [:]
    ) -> LinkIndex.Entry {
        LinkIndex.Entry(
            id: id,
            title: title,
            body: "",
            kind: .document,
            relationships: relationships
        )
    }

    // MARK: - Kinds

    @Test("Each relationship kind has a human-readable label")
    func kindsHaveLabels() {
        for kind in RelationshipKind.allCases {
            #expect(!kind.label.isEmpty)
        }
    }

    @Test("belongs_to and has are inverses of each other")
    func belongsToAndHasAreInverses() {
        #expect(RelationshipKind.belongsTo.inverse == .has)
        #expect(RelationshipKind.has.inverse == .belongsTo)
    }

    @Test("related_to is its own inverse")
    func relatedToIsSymmetric() {
        #expect(RelationshipKind.relatedTo.inverse == .relatedTo)
    }

    @Test("Frontmatter-style keys round-trip")
    func keysRoundTrip() {
        for kind in RelationshipKind.allCases {
            #expect(RelationshipKind(key: kind.key) == kind)
        }
    }

    @Test("An unknown key resolves to nil")
    func unknownKey() {
        #expect(RelationshipKind(key: "wat") == nil)
    }

    // MARK: - Declared relationships

    @Test("A declared relationship resolves to its target")
    func declaredRelationshipResolves() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        #expect(index.related(from: alphaID, kind: .belongsTo) == [betaID])
    }

    @Test("A relationship to a missing title is reported as broken")
    func brokenRelationship() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Nowhere"]]),
        ])
        #expect(index.related(from: alphaID, kind: .belongsTo).isEmpty)
        #expect(index.brokenTargets(from: alphaID) == ["Nowhere"])
    }

    @Test("Relationship targets may be written as wikilinks")
    func wikilinkSyntaxAccepted() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["[[Beta]]"]]),
            entry(betaID, "Beta"),
        ])
        #expect(index.related(from: alphaID, kind: .belongsTo) == [betaID])
    }

    // MARK: - Computed inverses

    @Test("A belongs_to produces an inverse has on the target")
    func inverseIsComputed() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        // Beta never declares anything, but has Alpha under its inverse.
        #expect(index.related(from: betaID, kind: .has) == [alphaID])
    }

    @Test("A has produces an inverse belongs_to on the target")
    func inverseWorksBothWays() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.has: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        #expect(index.related(from: betaID, kind: .belongsTo) == [alphaID])
    }

    @Test("related_to is visible from both ends")
    func symmetricRelationshipBothWays() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.relatedTo: ["Beta"]]),
            entry(betaID, "Beta"),
        ])
        #expect(index.related(from: alphaID, kind: .relatedTo) == [betaID])
        #expect(index.related(from: betaID, kind: .relatedTo) == [alphaID])
    }

    @Test("An explicit relationship is not duplicated by its computed inverse")
    func explicitAndInverseDoNotDuplicate() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.relatedTo: ["Beta"]]),
            entry(betaID, "Beta", relationships: [.relatedTo: ["Alpha"]]),
        ])
        #expect(index.related(from: alphaID, kind: .relatedTo) == [betaID])
        #expect(index.related(from: betaID, kind: .relatedTo) == [alphaID])
    }

    @Test("A self-relationship is ignored")
    func selfRelationshipIgnored() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.belongsTo: ["Alpha"]]),
        ])
        #expect(index.related(from: alphaID, kind: .belongsTo).isEmpty)
        #expect(index.related(from: alphaID, kind: .has).isEmpty)
    }

    @Test("Multiple targets in one relationship all resolve")
    func multipleTargets() {
        let index = LinkIndex(entries: [
            entry(alphaID, "Alpha", relationships: [.has: ["Beta", "Gamma"]]),
            entry(betaID, "Beta"),
            entry(gammaID, "Gamma"),
        ])
        #expect(Set(index.related(from: alphaID, kind: .has)) == [betaID, gammaID])
    }

    @Test("Body wikilinks stay separate from declared relationships")
    func bodyLinksAreNotRelationships() {
        let index = LinkIndex(entries: [
            LinkIndex.Entry(
                id: alphaID, title: "Alpha", body: "see [[Beta]]",
                kind: .document, relationships: [:]
            ),
            entry(betaID, "Beta"),
        ])
        #expect(index.outgoing(from: alphaID) == [betaID])
        #expect(index.related(from: alphaID, kind: .relatedTo).isEmpty)
    }

    @Test("An entry with no relationships answers emptily for every kind")
    func noRelationships() {
        let index = LinkIndex(entries: [entry(alphaID, "Alpha")])
        for kind in RelationshipKind.allCases {
            #expect(index.related(from: alphaID, kind: kind).isEmpty)
        }
    }
}
