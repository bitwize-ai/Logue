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

/// A property written by a build that knows a kind this one does not.
///
/// The failure this guards is severe and silent: decoding threw, the throw propagated out of
/// `WritingDocument.init(from:)`, and `DocumentStore`'s per-file `catch` skipped the file — so the
/// document vanished from the library. Rolling back a build must not lose documents.
@Suite("Unknown property kinds")
struct UnknownPropertyKindTests {
    private func decode(_ json: String) throws -> PropertyValue {
        try JSONDecoder().decode(PropertyValue.self, from: Data(json.utf8))
    }

    @Test("An unrecognised kind decodes instead of throwing")
    func unknownKindDecodes() throws {
        let value = try decode(#"{"kind":"reference","value":"doc-123"}"#)

        #expect(value == .unknown(kind: "reference", value: .string("doc-123")))
    }

    @Test("A document carrying one still decodes, rather than disappearing")
    func documentSurvives() throws {
        var doc = WritingDocument()
        doc.title = "Has a future property"
        var encoded = try JSONEncoder().encode(doc)

        // Rewrite one property as a kind this build does not have, the way a newer build would.
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["properties"] = ["status": ["kind": "reference", "value": "doc-123"]]
        encoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WritingDocument.self, from: encoded)
        #expect(decoded.title == "Has a future property")
        #expect(decoded.properties?["status"] == .unknown(kind: "reference", value: .string("doc-123")))
    }

    /// Tolerating the tag but dropping the payload would still lose the user's data the moment they
    /// went back to the newer build.
    @Test("The round trip is lossless, including nested values")
    func roundTripIsLossless() throws {
        let json = #"{"kind":"reference","value":{"id":"abc","weight":2,"tags":["a","b"],"live":true}}"#
        let value = try decode(json)

        let reEncoded = try JSONEncoder().encode(value)
        let again = try JSONDecoder().decode(PropertyValue.self, from: reEncoded)

        #expect(again == value)
        if case let .unknown(kind, payload) = value {
            #expect(kind == "reference")
            if case let .object(fields) = payload {
                #expect(fields["id"] == .string("abc"))
                #expect(fields["weight"] == .number(2))
                #expect(fields["tags"] == .array([.string("a"), .string("b")]))
                #expect(fields["live"] == .boolean(true))
            } else {
                Issue.record("Expected the payload to survive as an object")
            }
        } else {
            Issue.record("Expected an unknown kind")
        }
    }

    @Test("A missing value is tolerated rather than fatal")
    func missingValueTolerated() throws {
        #expect(try decode(#"{"kind":"reference"}"#) == .unknown(kind: "reference", value: .null))
    }

    @Test("Known kinds are unaffected")
    func knownKindsStillWork() throws {
        #expect(try decode(#"{"kind":"text","value":"hello"}"#) == .text("hello"))
        #expect(try decode(#"{"kind":"number","value":42}"#) == .number(42))
        #expect(try decode(#"{"kind":"boolean","value":true}"#) == .boolean(true))
        #expect(try decode(#"{"kind":"list","value":["a"]}"#) == .list(["a"]))
    }

    @Test("An unknown kind shows something rather than nothing")
    func unknownKindDisplays() throws {
        #expect(try decode(#"{"kind":"reference","value":"Design doc"}"#).displayString == "Design doc")
        #expect(try decode(#"{"kind":"rating","value":4}"#).displayString == "4")
    }
}
