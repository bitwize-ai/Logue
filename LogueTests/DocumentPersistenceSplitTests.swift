import Foundation
@testable import Logue
import Testing

/// Splitting a document into the half a person edits and the half the app derives.
///
/// This is the seam plain-markdown storage needs: content can live in a `.md` file
/// while AI-derived state stays encrypted, because derived state has no sensible
/// frontmatter form and is never hand-edited.
@Suite("DocumentPersistenceSplit")
struct DocumentPersistenceSplitTests {
    private func populated() -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Project Alpha"
        doc.body = "# Heading\n\nSome text.\n"
        doc.tags = ["urgent", "later"]
        doc.spaceID = UUID()
        doc.isPinned = true
        doc.icon = "📄"
        doc.widthMode = .wide
        doc.isOrganised = true
        doc.setProperty("status", value: .text("Active"))
        doc.setRelationship(.belongsTo, targets: ["Workspace"])

        // Derived
        doc.aiDetectionResult = "looks human"
        doc.plagiarismResult = "no matches"
        doc.rewriteResult = RewriteResult(
            style: "concise", originalText: "before", rewrittenText: "after"
        )
        return doc
    }

    // MARK: - Content half

    @Test("Content carries everything a person edits")
    func contentCarriesEditableFields() {
        let doc = populated()
        let content = doc.content

        #expect(content.id == doc.id)
        #expect(content.title == doc.title)
        #expect(content.body == doc.body)
        #expect(content.tags == doc.tags)
        #expect(content.spaceID == doc.spaceID)
        #expect(content.icon == doc.icon)
        #expect(content.isPinned == doc.isPinned)
        #expect(content.properties?["status"] == .text("Active"))
        #expect(content.relationships?["belongs_to"] == ["Workspace"])
    }

    @Test("Content round-trips through persistence")
    func contentRoundTrips() throws {
        let content = populated().content
        let decoded = try JSONDecoder().decode(
            DocumentContent.self, from: JSONEncoder().encode(content)
        )
        #expect(decoded.id == content.id)
        #expect(decoded.title == content.title)
        #expect(decoded.body == content.body)
        #expect(decoded.tags == content.tags)
        #expect(decoded.properties?["status"] == .text("Active"))
    }

    // MARK: - Derived half

    @Test("Derived carries the AI caches")
    func derivedCarriesAIState() {
        let doc = populated()
        let derived = doc.derived

        #expect(derived.id == doc.id)
        #expect(derived.aiDetectionResult == "looks human")
        #expect(derived.plagiarismResult == "no matches")
        #expect(derived.rewriteResult?.style == "concise")
    }

    @Test("Derived round-trips through persistence")
    func derivedRoundTrips() throws {
        let derived = populated().derived
        let decoded = try JSONDecoder().decode(
            DocumentDerived.self, from: JSONEncoder().encode(derived)
        )
        #expect(decoded.id == derived.id)
        #expect(decoded.aiDetectionResult == "looks human")
        #expect(decoded.rewriteResult?.rewrittenText == "after")
    }

    @Test("Derived carries no editable content")
    func derivedHasNoContent() throws {
        let derived = populated().derived
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(derived)
        ) as? [String: Any]

        // Body and title must not leak into the encrypted half — otherwise there are
        // two copies of the text and they can diverge.
        #expect(json?["body"] == nil)
        #expect(json?["title"] == nil)
    }

    // MARK: - Recomposition

    @Test("Content and derived recompose into the original document")
    func recomposes() {
        let original = populated()
        let rebuilt = WritingDocument(content: original.content, derived: original.derived)

        #expect(rebuilt.id == original.id)
        #expect(rebuilt.title == original.title)
        #expect(rebuilt.body == original.body)
        #expect(rebuilt.tags == original.tags)
        #expect(rebuilt.spaceID == original.spaceID)
        #expect(rebuilt.icon == original.icon)
        #expect(rebuilt.widthMode == original.widthMode)
        #expect(rebuilt.isOrganised == original.isOrganised)
        #expect(rebuilt.property("status") == .text("Active"))
        #expect(rebuilt.typedRelationships[.belongsTo] == ["Workspace"])
        #expect(rebuilt.aiDetectionResult == original.aiDetectionResult)
        #expect(rebuilt.rewriteResult == original.rewriteResult)
    }

    @Test("A document with no derived state recomposes with empty caches")
    func recomposesWithoutDerived() {
        let original = populated()
        let rebuilt = WritingDocument(content: original.content, derived: nil)

        #expect(rebuilt.title == original.title)
        #expect(rebuilt.body == original.body)
        #expect(rebuilt.aiDetectionResult == nil)
        #expect(rebuilt.rewriteResult == nil)
        #expect(rebuilt.chatMessages.isEmpty)
    }

    @Test("Recomposition keeps the content half's identity when the two disagree")
    func contentIdentityWins() {
        let original = populated()
        var strayDerived = original.derived
        strayDerived.id = UUID()

        let rebuilt = WritingDocument(content: original.content, derived: strayDerived)
        #expect(rebuilt.id == original.content.id)
    }

    @Test("Timestamps survive the split")
    func timestampsSurvive() {
        let original = populated()
        let rebuilt = WritingDocument(content: original.content, derived: original.derived)
        #expect(rebuilt.createdAt == original.createdAt)
        #expect(rebuilt.modifiedAt == original.modifiedAt)
    }

    @Test("Trash state survives the split")
    func trashStateSurvives() {
        var original = populated()
        original.isTrashed = true
        original.trashedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let rebuilt = WritingDocument(content: original.content, derived: original.derived)
        #expect(rebuilt.isTrashed)
        #expect(rebuilt.trashedAt == original.trashedAt)
    }

    // MARK: - Back-compatibility

    @Test("A legacy whole-document file still decodes")
    func legacyDocumentDecodes() throws {
        let legacy = """
        {
            "id": "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40",
            "title": "Legacy", "body": "Body", "goalMode": "casual",
            "createdAt": 0, "modifiedAt": 0, "isFavorited": false,
            "tags": [], "chatMessages": [], "isTrashed": false
        }
        """
        let doc = try JSONDecoder().decode(WritingDocument.self, from: Data(legacy.utf8))
        #expect(doc.title == "Legacy")
        #expect(doc.body == "Body")
    }

    @Test("An empty document splits and recomposes without loss")
    func emptyDocumentRoundTrips() {
        let original = WritingDocument()
        let rebuilt = WritingDocument(content: original.content, derived: original.derived)
        #expect(rebuilt.id == original.id)
        #expect(rebuilt.title == original.title)
    }
}
