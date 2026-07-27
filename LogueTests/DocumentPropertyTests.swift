import Foundation
@testable import Logue
import Testing

@Suite("DocumentProperties")
struct DocumentPropertyTests {
    // MARK: - Value type

    @Test("A text value round-trips")
    func textValueRoundTrips() throws {
        let value = PropertyValue.text("Active")
        let decoded = try JSONDecoder().decode(
            PropertyValue.self, from: JSONEncoder().encode(value)
        )
        #expect(decoded == value)
    }

    @Test("A number value round-trips")
    func numberValueRoundTrips() throws {
        let value = PropertyValue.number(42.5)
        let decoded = try JSONDecoder().decode(
            PropertyValue.self, from: JSONEncoder().encode(value)
        )
        #expect(decoded == value)
    }

    @Test("A date value round-trips")
    func dateValueRoundTrips() throws {
        let value = PropertyValue.date(Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try JSONDecoder().decode(
            PropertyValue.self, from: JSONEncoder().encode(value)
        )
        #expect(decoded == value)
    }

    @Test("A boolean value round-trips")
    func boolValueRoundTrips() throws {
        let decoded = try JSONDecoder().decode(
            PropertyValue.self, from: JSONEncoder().encode(PropertyValue.boolean(true))
        )
        #expect(decoded == .boolean(true))
    }

    @Test("A list value round-trips")
    func listValueRoundTrips() throws {
        let value = PropertyValue.list(["a", "b"])
        let decoded = try JSONDecoder().decode(
            PropertyValue.self, from: JSONEncoder().encode(value)
        )
        #expect(decoded == value)
    }

    @Test("Every value renders a display string")
    func displayStrings() {
        #expect(PropertyValue.text("Active").displayString == "Active")
        #expect(PropertyValue.boolean(true).displayString == "Yes")
        #expect(PropertyValue.boolean(false).displayString == "No")
        #expect(PropertyValue.list(["a", "b"]).displayString == "a, b")
        #expect(PropertyValue.number(3).displayString == "3")
        #expect(PropertyValue.number(3.5).displayString == "3.5")
        #expect(PropertyValue.date(Date()).displayString.isEmpty == false)
    }

    // MARK: - Keys

    @Test("Suggested keys expose stable frontmatter names")
    func suggestedKeys() {
        #expect(PropertyKey.status.rawValue == "status")
        #expect(PropertyKey.type.rawValue == "type")
        #expect(PropertyKey.dueDate.rawValue == "due_date")
        #expect(PropertyKey.url.rawValue == "url")
    }

    @Test("A key is sanitised into a usable frontmatter name")
    func keySanitisation() {
        #expect(PropertyKey.sanitisedKey("Due Date") == "due_date")
        #expect(PropertyKey.sanitisedKey("  Status  ") == "status")
        #expect(PropertyKey.sanitisedKey("weird!!chars") == "weirdchars")
    }

    @Test("An underscore-prefixed key is refused as system-reserved")
    func systemKeysRefused() {
        #expect(PropertyKey.sanitisedKey("_internal") == nil)
    }

    @Test("An empty or symbol-only key is refused")
    func emptyKeyRefused() {
        #expect(PropertyKey.sanitisedKey("") == nil)
        #expect(PropertyKey.sanitisedKey("!!!") == nil)
    }

    @Test("An over-long key is truncated rather than refused")
    func longKeyTruncated() throws {
        let key = try #require(PropertyKey.sanitisedKey(String(repeating: "a", count: 200)))
        #expect(key.count <= PropertyKey.maxKeyLength)
    }

    // MARK: - Document integration

    @Test("Legacy JSON without properties decodes without throwing")
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
        #expect(doc.propertyValues.isEmpty)
    }

    @Test("Setting and reading a property round-trips through persistence")
    func propertyRoundTrip() throws {
        var doc = WritingDocument()
        doc.setProperty("status", value: .text("Active"))

        let decoded = try JSONDecoder().decode(WritingDocument.self, from: JSONEncoder().encode(doc))
        #expect(decoded.property("status") == .text("Active"))
    }

    @Test("Setting nil removes a property")
    func settingNilRemoves() {
        var doc = WritingDocument()
        doc.setProperty("status", value: .text("Active"))
        doc.setProperty("status", value: nil)
        #expect(doc.property("status") == nil)
    }

    @Test("A key is sanitised on assignment")
    func keySanitisedOnSet() {
        var doc = WritingDocument()
        doc.setProperty("Due Date", value: .text("Friday"))
        #expect(doc.property("due_date") == .text("Friday"))
    }

    @Test("A system-reserved key is refused on assignment")
    func systemKeyRefusedOnSet() {
        var doc = WritingDocument()
        doc.setProperty("_secret", value: .text("nope"))
        #expect(doc.propertyValues.isEmpty)
    }

    @Test("Property keys are listed in a stable sorted order")
    func stableKeyOrder() {
        var doc = WritingDocument()
        doc.setProperty("zeta", value: .text("z"))
        doc.setProperty("alpha", value: .text("a"))
        #expect(doc.propertyKeys == ["alpha", "zeta"])
    }

    @Test("Reading a missing property returns nil")
    func missingProperty() {
        #expect(WritingDocument().property("nope") == nil)
    }
}
