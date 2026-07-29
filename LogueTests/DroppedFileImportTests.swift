import Foundation
@testable import Logue
import Testing

/// Reading a markdown file someone put in the folder by hand.
@Suite("Dropped file import")
struct DroppedFileImportTests {
    @Test("The filename becomes the title when the file has none")
    func filenameBecomesTitle() throws {
        let fields = try #require(
            DroppedFileImport.fields(fileContents: "some prose", filename: "Shopping List.md")
        )

        #expect(fields.title == "Shopping List")
        #expect(fields.body == "some prose")
    }

    @Test("An explicit title wins over the filename")
    func explicitTitleWins() throws {
        let contents = """
        ---
        title: Real Title
        ---
        body
        """

        let fields = try #require(
            DroppedFileImport.fields(fileContents: contents, filename: "whatever.md")
        )
        #expect(fields.title == "Real Title")
    }

    @Test("An empty title falls back to the filename")
    func blankTitleFallsBack() throws {
        let contents = """
        ---
        title:
        ---
        body
        """

        let fields = try #require(
            DroppedFileImport.fields(fileContents: contents, filename: "Notes.md")
        )
        #expect(fields.title == "Notes")
    }

    @Test("Tags are read from frontmatter")
    func readsTags() throws {
        let contents = """
        ---
        tags:
          - draft
          - ideas
        ---
        body
        """

        let fields = try #require(
            DroppedFileImport.fields(fileContents: contents, filename: "a.md")
        )
        #expect(fields.tags == ["draft", "ideas"])
    }

    /// The guard that stops a real document being adopted a second time under a new identity,
    /// which would leave two documents sharing one file.
    @Test("A file that already has an identifier is not treated as new")
    func refusesIdentifiedFile() {
        var doc = WritingDocument()
        doc.title = "Existing"
        let rendered = MarkdownDocumentFile.render(doc.content)

        #expect(DroppedFileImport.fields(fileContents: rendered, filename: "Existing.md") == nil)
    }

    @Test("A file with an unusable name still gets a title")
    func namelessFileGetsATitle() throws {
        let fields = try #require(DroppedFileImport.fields(fileContents: "text", filename: ".md"))

        #expect(fields.title == "Untitled Document")
    }

    // MARK: - This path rewrites the file, so it must not reshape it

    /// `adopt` renders what this returns and writes it back, so trimming the body rewrote a note
    /// that opened with an indented code block into a paragraph — in the user's own file.
    @Test("Leading indentation is content, not stray whitespace")
    func leadingIndentationSurvives() throws {
        let fields = try #require(
            DroppedFileImport.fields(fileContents: "\n    indented code block", filename: "n.md")
        )
        #expect(fields.body.contains("    indented code block"))
    }

    /// The 120-character cap exists because imported titles reach LLM prompts. Applying it to a
    /// file the user already owns truncates their text on disk with no way back.
    @Test("A long title is not truncated on a file we already hold")
    func longTitleIsNotTruncated() throws {
        let long = String(repeating: "a", count: 250)
        let fields = try #require(
            DroppedFileImport.fields(fileContents: "# \(long)\n\nBody.", filename: "n.md")
        )
        #expect(fields.title.count == 250)
    }

    /// `DocumentContent` has nowhere to put a modified date, so consuming these on this path took
    /// the key out of properties and then dropped it — deleting `modified:` from the file.
    @Test("A modified date is kept as a property rather than deleted")
    func modifiedIsKeptAsAProperty() throws {
        let fields = try #require(DroppedFileImport.fields(
            fileContents: "---\ntitle: Post\nmodified: 2025-01-02\n---\nBody.",
            filename: "n.md"
        ))
        #expect(fields.properties["modified"] != nil)
    }

    /// A file already in the folder has no dialog to explain a refusal, and nothing marks it — so
    /// a silently un-adoptable file is re-read on every scan, forever.
    @Test("An oversized file in the folder is still adopted")
    func oversizedFileIsStillAdopted() throws {
        let big = String(repeating: "x", count: MarkdownImport.maxFileBytes + 1)
        let fields = try #require(DroppedFileImport.fields(fileContents: big, filename: "big.md"))
        #expect(fields.body.count > MarkdownImport.maxFileBytes)
    }

    @Test("A whitespace-only file in the folder is still adopted")
    func whitespaceOnlyFileIsStillAdopted() throws {
        #expect(DroppedFileImport.fields(fileContents: "   \n\n  ", filename: "n.md") != nil)
    }
}
