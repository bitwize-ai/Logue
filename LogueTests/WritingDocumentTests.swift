import Foundation
@testable import Logue
import Testing

@Suite("WritingDocument")
struct WritingDocumentTests {
    @Test("Document generates default UUID and title")
    func defaults() {
        let doc = WritingDocument()
        #expect(doc.title == "Untitled Document")
        #expect(doc.body.isEmpty)
        #expect(doc.isPinned == false)
        #expect(doc.score == nil)
    }

    @Test("Word count works")
    func wordCount() {
        var doc = WritingDocument()
        doc.body = "This is a simple test document."
        #expect(doc.wordCount == 6)

        doc.body = "   Whitespace strings  should  not count space    "
        #expect(doc.wordCount == 6)
    }

    @Test("Reading time computes correctly")
    func readingTime() {
        var doc = WritingDocument()
        // Create 238 words
        let wordStr = "word "
        doc.body = String(repeating: wordStr, count: 238)

        #expect(doc.readingTimeMinutes == 1.0)
        #expect(doc.readingTimeLabel == "1 min read")

        doc.body = "Short content"
        // < 1 min read label
        #expect(doc.readingTimeMinutes < 1.0)
        #expect(doc.readingTimeLabel == "< 1 min read")

        // 238 * 2.5 words = 595 words
        doc.body = String(repeating: wordStr, count: 595)
        #expect(doc.readingTimeMinutes == 2.5)
        // ceil(2.5) == 3
        #expect(doc.readingTimeLabel == "3 min read")
    }

    @Test("Snippet generated correctly")
    func snippet() {
        var doc = WritingDocument()
        doc.body = "   Trim this part away. "
        #expect(doc.snippet == "Trim this part away.")

        let longText = String(repeating: "Hello world ", count: 20) // 12 * 20 = 240
        doc.body = longText
        let expectedSnippet = String(longText.prefix(120)) + "…"
        #expect(doc.snippet == expectedSnippet)
        // Check that its string count is strictly 121 (120 chars + ellipsis)
        #expect(doc.snippet.count == 121)
    }
}
