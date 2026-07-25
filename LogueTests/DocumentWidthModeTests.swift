import Foundation
@testable import Logue
import Testing

@Suite("DocumentWidthMode")
struct DocumentWidthModeTests {
    /// Legacy documents were persisted before `widthMode` existed. Decoding must
    /// tolerate the missing key rather than throwing, or every existing document
    /// becomes unreadable after the app updates.
    @Test("Legacy JSON without widthMode decodes to the normal default")
    func legacyJSONDecodesToNormal() throws {
        let legacy = """
        {
            "id": "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40",
            "title": "Legacy Doc",
            "body": "Body text",
            "goalMode": "casual",
            "createdAt": 0,
            "modifiedAt": 0,
            "isFavorited": false,
            "tags": [],
            "chatMessages": [],
            "isTrashed": false
        }
        """
        let data = Data(legacy.utf8)
        let doc = try JSONDecoder().decode(WritingDocument.self, from: data)

        #expect(doc.widthMode == .normal)
    }

    @Test("New documents default to normal width")
    func newDocumentDefault() {
        #expect(WritingDocument().widthMode == .normal)
    }

    @Test("Width mode survives an encode/decode round trip")
    func roundTrip() throws {
        var doc = WritingDocument()
        doc.widthMode = .wide

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(WritingDocument.self, from: data)

        #expect(decoded.widthMode == .wide)
    }

    @Test("Wide mode allows a larger content width than normal")
    func wideIsWiderThanNormal() {
        #expect(DocumentWidthMode.wide.maxContentWidth > DocumentWidthMode.normal.maxContentWidth)
    }

    @Test("Toggling returns the opposite mode")
    func toggling() {
        #expect(DocumentWidthMode.normal.toggled == .wide)
        #expect(DocumentWidthMode.wide.toggled == .normal)
    }
}
