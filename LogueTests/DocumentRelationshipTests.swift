import Foundation
@testable import Logue
import Testing

@Suite("DocumentRelationships")
struct DocumentRelationshipTests {
    @Test("Legacy JSON without relationships decodes without throwing")
    func legacyJSONDecodes() throws {
        let legacy = """
        {
            "id": "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40",
            "title": "Legacy", "body": "", "goalMode": "casual",
            "createdAt": 0, "modifiedAt": 0, "isFavorited": false,
            "tags": [], "chatMessages": [], "isTrashed": false
        }
        """
        let doc = try JSONDecoder().decode(WritingDocument.self, from: Data(legacy.utf8))
        #expect(doc.typedRelationships.isEmpty)
    }

    @Test("A new document starts with no relationships")
    func newDocumentHasNone() {
        #expect(WritingDocument().typedRelationships.isEmpty)
    }

    @Test("Relationships survive an encode/decode round trip")
    func roundTrip() throws {
        var doc = WritingDocument()
        doc.setRelationship(.belongsTo, targets: ["Project Alpha"])

        let decoded = try JSONDecoder().decode(WritingDocument.self, from: JSONEncoder().encode(doc))
        #expect(decoded.typedRelationships[.belongsTo] == ["Project Alpha"])
    }

    @Test("Relationships persist under their frontmatter key")
    func persistsUnderFrontmatterKey() throws {
        var doc = WritingDocument()
        doc.setRelationship(.belongsTo, targets: ["Alpha"])

        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(doc)
        ) as? [String: Any]
        let relationships = json?["relationships"] as? [String: Any]
        #expect(relationships?["belongs_to"] != nil)
    }

    @Test("Setting an empty target list clears the relationship")
    func emptyTargetsClears() {
        var doc = WritingDocument()
        doc.setRelationship(.relatedTo, targets: ["Alpha"])
        doc.setRelationship(.relatedTo, targets: [])
        #expect(doc.typedRelationships[.relatedTo] == nil)
    }

    @Test("Blank targets are discarded")
    func blankTargetsDiscarded() {
        var doc = WritingDocument()
        doc.setRelationship(.has, targets: ["Alpha", "   ", ""])
        #expect(doc.typedRelationships[.has] == ["Alpha"])
    }

    @Test("Duplicate targets are stored once")
    func duplicateTargetsDeduplicated() {
        var doc = WritingDocument()
        doc.setRelationship(.has, targets: ["Alpha", "alpha", "Alpha"])
        #expect(doc.typedRelationships[.has]?.count == 1)
    }

    @Test("An unknown frontmatter key is ignored rather than crashing")
    func unknownKeyIgnored() {
        var doc = WritingDocument()
        doc.relationships = ["not_a_relationship": ["Alpha"], "has": ["Beta"]]
        #expect(doc.typedRelationships == [.has: ["Beta"]])
    }

    @Test("The graph picks up relationships declared on a document")
    func graphUsesDocumentRelationships() {
        var alpha = WritingDocument()
        alpha.title = "Alpha"
        alpha.setRelationship(.belongsTo, targets: ["Beta"])
        var beta = WritingDocument()
        beta.title = "Beta"

        let index = LinkIndex.build(documents: [alpha, beta], meetings: [])

        #expect(index.related(from: alpha.id, kind: .belongsTo) == [beta.id])
        #expect(index.related(from: beta.id, kind: .has) == [alpha.id])
    }
}
