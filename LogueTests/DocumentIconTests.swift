import Foundation
@testable import Logue
import Testing

@Suite("DocumentIcon")
struct DocumentIconTests {
    @Test("Legacy JSON without an icon decodes without throwing")
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
        #expect(doc.icon == nil)
    }

    @Test("Icon survives an encode/decode round trip")
    func roundTrip() throws {
        var doc = WritingDocument()
        doc.icon = "📄"
        let decoded = try JSONDecoder().decode(WritingDocument.self, from: JSONEncoder().encode(doc))
        #expect(decoded.icon == "📄")
    }

    @Test("A single emoji is accepted")
    func acceptsEmoji() {
        #expect(DocumentIcon.sanitised("📄") == "📄")
    }

    @Test("Control characters and newlines are rejected")
    func rejectsControlCharacters() {
        #expect(DocumentIcon.sanitised("a\nb") == nil)
        #expect(DocumentIcon.sanitised("\u{0}") == nil)
    }

    @Test("An over-long string is rejected rather than truncated mid-emoji")
    func rejectsOverLongInput() {
        #expect(DocumentIcon.sanitised("📄📄📄📄📄📄") == nil)
    }

    @Test("Empty or whitespace-only input clears the icon")
    func emptyClearsIcon() {
        #expect(DocumentIcon.sanitised("") == nil)
        #expect(DocumentIcon.sanitised("   ") == nil)
    }

    @Test("A multi-scalar emoji counts as one character")
    func multiScalarEmojiAccepted() {
        #expect(DocumentIcon.sanitised("👩‍💻") == "👩‍💻")
    }
}
