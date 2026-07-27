import Foundation
@testable import Logue
import Testing

/// Mapping a document to a plain `.md` file and back.
///
/// The encrypted store stays authoritative, so a mirror file must carry enough to
/// identify which document it belongs to and to apply an external edit back.
@Suite("MirrorFile")
struct MirrorFileTests {
    private func document(
        title: String = "Project Alpha",
        body: String = "Body text"
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        return doc
    }

    // MARK: - Rendering

    @Test("The body follows the frontmatter")
    func bodyFollowsFrontmatter() {
        let text = MirrorFile.render(document(body: "Hello"))
        #expect(text.hasSuffix("Hello\n"))
        #expect(text.hasPrefix("---\n"))
    }

    @Test("The identifier is written so the file maps back to its document")
    func writesIdentifier() {
        let doc = document()
        let parsed = MarkdownFrontmatter.parse(MirrorFile.render(doc))
        #expect(parsed.fields[MirrorFile.identifierKey] == .scalar(doc.id.uuidString))
    }

    @Test("The title is written")
    func writesTitle() {
        let parsed = MarkdownFrontmatter.parse(MirrorFile.render(document(title: "Alpha")))
        #expect(parsed.fields["title"] == .scalar("Alpha"))
    }

    @Test("Tags are written as a list")
    func writesTags() {
        var doc = document()
        doc.tags = ["urgent", "later"]
        let parsed = MarkdownFrontmatter.parse(MirrorFile.render(doc))
        #expect(parsed.fields["tags"] == .list(["urgent", "later"]))
    }

    @Test("Properties are written under their own keys")
    func writesProperties() {
        var doc = document()
        doc.setProperty("status", value: .text("Active"))
        let parsed = MarkdownFrontmatter.parse(MirrorFile.render(doc))
        #expect(parsed.fields["status"] == .scalar("Active"))
    }

    @Test("Relationships are written as wikilink lists")
    func writesRelationships() {
        var doc = document()
        doc.setRelationship(.belongsTo, targets: ["Workspace"])
        let parsed = MarkdownFrontmatter.parse(MirrorFile.render(doc))
        #expect(parsed.fields["belongs_to"] == .list(["[[Workspace]]"]))
    }

    @Test("A document with no metadata still renders a valid file")
    func minimalDocument() {
        let text = MirrorFile.render(document(title: "", body: ""))
        #expect(text.contains(MirrorFile.identifierKey))
    }

    @Test("Rendering the same document twice produces identical bytes")
    func renderIsDeterministic() {
        var doc = document()
        doc.tags = ["b", "a"]
        doc.setProperty("status", value: .text("Active"))
        doc.setProperty("author", value: .text("Me"))
        #expect(MirrorFile.render(doc) == MirrorFile.render(doc))
    }

    // MARK: - Identifying

    @Test("The identifier can be read back from a file")
    func readsIdentifier() {
        let doc = document()
        #expect(MirrorFile.identifier(in: MirrorFile.render(doc)) == doc.id)
    }

    @Test("A file with no identifier yields nil rather than guessing")
    func noIdentifier() {
        #expect(MirrorFile.identifier(in: "---\ntitle: A\n---\nbody") == nil)
    }

    @Test("A malformed identifier yields nil")
    func malformedIdentifier() {
        let text = "---\n\(MirrorFile.identifierKey): not-a-uuid\n---\n"
        #expect(MirrorFile.identifier(in: text) == nil)
    }

    // MARK: - Applying an external edit

    @Test("An edited body is applied back to the document")
    func appliesEditedBody() {
        let doc = document(body: "old")
        let edited = MirrorFile.render(doc).replacingOccurrences(of: "old", with: "new")
        let updated = MirrorFile.applying(edited, to: doc)
        #expect(updated?.body == "new")
    }

    @Test("An edited title is applied back")
    func appliesEditedTitle() {
        let doc = document(title: "Old")
        let edited = MirrorFile.render(doc).replacingOccurrences(of: "title: Old", with: "title: New")
        #expect(MirrorFile.applying(edited, to: doc)?.title == "New")
    }

    @Test("Edited tags are applied back")
    func appliesEditedTags() {
        var doc = document()
        doc.tags = ["one"]
        let edited = MirrorFile.render(doc).replacingOccurrences(of: "- one", with: "- two")
        #expect(MirrorFile.applying(edited, to: doc)?.tags == ["two"])
    }

    @Test("An edit for a different document is refused")
    func refusesMismatchedIdentifier() {
        let edited = MirrorFile.render(document())
        // Applying to a *different* document must not silently overwrite it.
        #expect(MirrorFile.applying(edited, to: document()) == nil)
    }

    @Test("A file with no identifier is refused")
    func refusesMissingIdentifier() {
        #expect(MirrorFile.applying("---\ntitle: A\n---\nbody", to: document()) == nil)
    }

    @Test("Fields absent from the file are left untouched on the document")
    func absentFieldsPreserved() {
        var doc = document()
        doc.setProperty("status", value: .text("Active"))
        // A file carrying only the identifier and body.
        let stripped = "---\n\(MirrorFile.identifierKey): \(doc.id.uuidString)\n---\nnew body"
        let updated = MirrorFile.applying(stripped, to: doc)
        #expect(updated?.body == "new body")
        #expect(updated?.property("status") == .text("Active"))
    }

    @Test("Applying an unchanged file reports no change")
    func unchangedFileDetectable() {
        let doc = document()
        #expect(MirrorFile.hasChanges(MirrorFile.render(doc), comparedTo: doc) == false)
    }

    @Test("Applying a changed file reports a change")
    func changedFileDetectable() {
        let doc = document(body: "old")
        let edited = MirrorFile.render(doc).replacingOccurrences(of: "old", with: "new")
        #expect(MirrorFile.hasChanges(edited, comparedTo: doc))
    }

    // MARK: - Round trip

    @Test("A full document round-trips through a mirror file")
    func fullRoundTrip() throws {
        var doc = document(title: "Plan: Q3", body: "# Heading\n\nSome *text* with [[a link]].\n")
        doc.tags = ["urgent"]
        doc.setProperty("status", value: .text("Active"))
        doc.setRelationship(.relatedTo, targets: ["Other"])

        let restored = try #require(MirrorFile.applying(MirrorFile.render(doc), to: doc))

        #expect(restored.title == doc.title)
        #expect(restored.body == doc.body)
        #expect(restored.tags == doc.tags)
        #expect(restored.property("status") == .text("Active"))
        #expect(restored.typedRelationships[.relatedTo] == ["Other"])
    }

    @Test("Unicode content round-trips")
    func unicodeRoundTrip() throws {
        let doc = document(title: "会議メモ", body: "👩‍💻 記録\n")
        let restored = try #require(MirrorFile.applying(MirrorFile.render(doc), to: doc))
        #expect(restored.title == "会議メモ")
        #expect(restored.body == "👩‍💻 記録\n")
    }
}
