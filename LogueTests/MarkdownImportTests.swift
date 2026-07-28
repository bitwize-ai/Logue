import Foundation
@testable import Logue
import Testing

@Suite("MarkdownImport")
struct MarkdownImportTests {
    // MARK: - Title Precedence

    @Test("The filename becomes the title when the file has no heading")
    func filenameTitle() throws {
        let doc = try MarkdownImport.document(fileName: "Meeting Prep.md", contents: "Some notes.")
        #expect(doc.title == "Meeting Prep")
        #expect(doc.body == "Some notes.")
    }

    @Test("A leading H1 becomes the title and is removed from the body")
    func headingTitle() throws {
        let doc = try MarkdownImport.document(
            fileName: "export-0042.md",
            contents: "# Quarterly Plan\n\nGoals for Q3."
        )
        #expect(doc.title == "Quarterly Plan")
        #expect(doc.body == "Goals for Q3.")
    }

    @Test("A frontmatter title wins over an H1, and the block is stripped")
    func frontmatterTitle() throws {
        let contents = """
        ---
        title: "From Trilium"
        tags: [a, b]
        ---
        # Different Heading

        Body text.
        """
        let doc = try MarkdownImport.document(fileName: "note.md", contents: contents)
        #expect(doc.title == "From Trilium")
        #expect(doc.body == "# Different Heading\n\nBody text.")
    }

    @Test("Frontmatter without a title still strips the block and falls back to the H1")
    func frontmatterWithoutTitle() throws {
        let contents = "---\ntags: [x]\n---\n# Real Title\nText."
        let doc = try MarkdownImport.document(fileName: "note.md", contents: contents)
        #expect(doc.title == "Real Title")
        #expect(doc.body == "Text.")
    }

    @Test("An unclosed frontmatter fence is treated as ordinary content")
    func unclosedFrontmatter() throws {
        let contents = "---\ntitle: never closed\nplain text"
        let doc = try MarkdownImport.document(fileName: "note.md", contents: contents)
        #expect(doc.title == "note")
        #expect(doc.body == contents)
    }

    @Test("An H1 after blank lines is still promoted to the title")
    func headingAfterBlankLines() throws {
        let doc = try MarkdownImport.document(fileName: "n.md", contents: "\n\n# Late Title\nBody.")
        #expect(doc.title == "Late Title")
        #expect(doc.body == "Body.")
    }

    @Test("An H2 is not a title source")
    func h2IsNotATitle() throws {
        let doc = try MarkdownImport.document(fileName: "n.md", contents: "## Section\nBody.")
        #expect(doc.title == "n")
        #expect(doc.body == "## Section\nBody.")
    }

    // MARK: - Sanitisation

    @Test("Control characters are stripped from a derived title and length is capped")
    func titleSanitised() throws {
        let long = String(repeating: "a", count: 400)
        let doc = try MarkdownImport.document(fileName: "n.md", contents: "# \u{07}\(long)\nx")
        #expect(doc.title.count == MarkdownImport.maxTitleLength)
        #expect(!doc.title.contains("\u{07}"))
    }

    @Test("A heading-only file imports with an empty body")
    func headingOnlyFile() throws {
        let doc = try MarkdownImport.document(fileName: "n.md", contents: "# Just a Title")
        #expect(doc.title == "Just a Title")
        #expect(doc.body.isEmpty)
    }

    // MARK: - Rejection

    @Test("Whitespace-only files are rejected")
    func emptyFileRejected() {
        #expect(throws: MarkdownImport.ImportError.emptyFile) {
            try MarkdownImport.document(fileName: "empty.md", contents: "   \n\n  ")
        }
    }

    @Test("Unsupported extensions are rejected", arguments: ["note.pdf", "note.docx", "note"])
    func unsupportedExtension(fileName: String) {
        #expect(throws: MarkdownImport.ImportError.self) {
            try MarkdownImport.document(fileName: fileName, contents: "hello")
        }
    }

    @Test("Supported extensions are accepted", arguments: ["a.md", "b.markdown", "c.txt", "D.MD"])
    func supportedExtensions(fileName: String) throws {
        let doc = try MarkdownImport.document(fileName: fileName, contents: "hello")
        #expect(doc.body == "hello")
    }

    @Test("Files over the size limit are rejected")
    func oversizedFileRejected() {
        let big = String(repeating: "x", count: MarkdownImport.maxFileBytes + 1)
        #expect(throws: MarkdownImport.ImportError.fileTooLarge(bytes: big.utf8.count)) {
            try MarkdownImport.document(fileName: "big.md", contents: big)
        }
    }

    @Test("Unicode contents and filenames survive intact")
    func unicodeSurvives() throws {
        let doc = try MarkdownImport.document(
            fileName: "日記 📓.md",
            contents: "# こんにちは 👋\n内容です。"
        )
        #expect(doc.title == "こんにちは 👋")
        #expect(doc.body == "内容です。")
    }
}
