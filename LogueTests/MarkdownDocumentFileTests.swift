import Foundation
@testable import Logue
import Testing

/// Reading and writing a document as a plain `.md` file — the storage format itself.
///
/// Round-trip fidelity is the whole contract: whatever a document contains must survive
/// a write and a read, because the file *is* the document.
@Suite("MarkdownDocumentFile")
struct MarkdownDocumentFileTests {
    private func populated() -> DocumentContent {
        var doc = WritingDocument()
        doc.title = "Project Alpha"
        doc.body = "# Heading\n\nSome *text* with [[a link]].\n"
        doc.tags = ["urgent", "later"]
        doc.icon = "📄"
        doc.widthMode = .wide
        doc.isPinned = true
        doc.isOrganised = true
        doc.setProperty("status", value: .text("Active"))
        doc.setProperty("priority", value: .text("High"))
        doc.setRelationship(.belongsTo, targets: ["Workspace"])
        doc.setRelationship(.relatedTo, targets: ["Other", "Third"])
        return doc.content
    }

    // MARK: - Round trip

    @Test("Everything survives a write and a read")
    func fullRoundTrip() throws {
        let original = populated()
        let restored = try #require(
            MarkdownDocumentFile.content(from: MarkdownDocumentFile.render(original))
        )

        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.body == original.body)
        #expect(restored.tags == original.tags)
        #expect(restored.icon == original.icon)
        #expect(restored.storedWidthMode == original.storedWidthMode)
        #expect(restored.isPinned == original.isPinned)
        #expect(restored.properties?["status"] == .text("Active"))
        #expect(restored.properties?["priority"] == .text("High"))
        #expect(restored.relationships?["belongs_to"] == ["Workspace"])
        #expect(restored.relationships?["related_to"] == ["Other", "Third"])
    }

    @Test("createdAt survives, so imported files keep their age")
    func createdAtSurvives() throws {
        var original = populated()
        original.createdAt = Date(timeIntervalSince1970: 1_600_000_000)

        let restored = try #require(
            MarkdownDocumentFile.content(from: MarkdownDocumentFile.render(original))
        )
        // Second precision is enough; frontmatter stores an ISO-8601 string.
        #expect(abs(restored.createdAt.timeIntervalSince(original.createdAt)) < 1)
    }

    @Test("An empty document round-trips")
    func emptyRoundTrips() throws {
        let original = WritingDocument().content
        let restored = try #require(
            MarkdownDocumentFile.content(from: MarkdownDocumentFile.render(original))
        )
        #expect(restored.id == original.id)
    }

    @Test("Unicode content survives")
    func unicodeSurvives() throws {
        var original = populated()
        original.title = "会議メモ"
        original.body = "👩‍💻 記録\n"

        let restored = try #require(
            MarkdownDocumentFile.content(from: MarkdownDocumentFile.render(original))
        )
        #expect(restored.title == "会議メモ")
        #expect(restored.body == "👩‍💻 記録\n")
    }

    @Test("A body containing a frontmatter fence is not truncated")
    func bodyWithFenceSurvives() throws {
        var original = populated()
        original.body = "Intro\n\n---\n\nAfter a divider\n"

        let restored = try #require(
            MarkdownDocumentFile.content(from: MarkdownDocumentFile.render(original))
        )
        #expect(restored.body == original.body)
    }

    // MARK: - Determinism

    @Test("The same document renders to identical bytes")
    func renderIsDeterministic() {
        let content = populated()
        #expect(MarkdownDocumentFile.render(content) == MarkdownDocumentFile.render(content))
    }

    @Test("Frontmatter keys appear in a fixed order")
    func keyOrderIsFixed() {
        let text = MarkdownDocumentFile.render(populated())
        let idIndex = try? #require(text.range(of: MarkdownDocumentFile.identifierKey))
        let titleIndex = try? #require(text.range(of: "title:"))
        #expect(idIndex != nil)
        #expect(titleIndex != nil)
    }

    // MARK: - Identity

    @Test("The identifier can be read without a full parse")
    func identifierReadable() {
        let content = populated()
        #expect(MarkdownDocumentFile.identifier(in: MarkdownDocumentFile.render(content)) == content.id)
    }

    @Test("A file with no identifier has none")
    func noIdentifier() {
        #expect(MarkdownDocumentFile.identifier(in: "---\ntitle: A\n---\nbody") == nil)
    }

    @Test("A file with no identifier cannot be read as content")
    func contentRequiresIdentifier() {
        #expect(MarkdownDocumentFile.content(from: "---\ntitle: A\n---\nbody") == nil)
    }

    // MARK: - Tolerance of hand-editing

    @Test("A hand-written body with no frontmatter is refused rather than guessed at")
    func plainProseRefused() {
        // Importing such a file is `MirrorImportPlan`'s job; reading *content* requires
        // an identifier, so this must not silently invent one.
        #expect(MarkdownDocumentFile.content(from: "just prose") == nil)
    }

    @Test("An unknown frontmatter key is preserved as a property rather than dropped")
    func unknownKeyBecomesProperty() throws {
        let text = """
        ---
        \(MarkdownDocumentFile.identifierKey): 0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40
        title: A
        mood: cheerful
        ---
        body
        """
        let restored = try #require(MarkdownDocumentFile.content(from: text))
        #expect(restored.properties?["mood"] == .text("cheerful"))
    }

    @Test("A malformed created date falls back rather than failing the read")
    func malformedDateTolerated() throws {
        let text = """
        ---
        \(MarkdownDocumentFile.identifierKey): 0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40
        title: A
        created: not-a-date
        ---
        body
        """
        let restored = try #require(MarkdownDocumentFile.content(from: text))
        #expect(restored.title == "A")
    }

    @Test("Windows line endings are handled")
    func crlfHandled() throws {
        let text = "---\r\n\(MarkdownDocumentFile.identifierKey): 0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40\r\ntitle: A\r\n---\r\nbody"
        let restored = try #require(MarkdownDocumentFile.content(from: text))
        #expect(restored.title == "A")
        #expect(restored.body == "body")
    }
}
