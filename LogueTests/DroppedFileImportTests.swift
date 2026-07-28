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
}
