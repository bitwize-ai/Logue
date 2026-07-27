import AppKit
@testable import Logue
import Testing

@Suite("WikiLinkURL")
struct WikiLinkURLTests {
    @Test("A simple target round-trips")
    func simpleRoundTrip() throws {
        let url = try #require(WikiLinkURL.url(for: "Memo"))
        #expect(WikiLinkURL.target(from: url) == "Memo")
    }

    @Test("A target with spaces round-trips")
    func spacesRoundTrip() throws {
        let url = try #require(WikiLinkURL.url(for: "Project Alpha"))
        #expect(WikiLinkURL.target(from: url) == "Project Alpha")
    }

    @Test("A unicode target round-trips")
    func unicodeRoundTrip() throws {
        let url = try #require(WikiLinkURL.url(for: "会議メモ"))
        #expect(WikiLinkURL.target(from: url) == "会議メモ")
    }

    @Test("An emoji target round-trips")
    func emojiRoundTrip() throws {
        let url = try #require(WikiLinkURL.url(for: "👩‍💻 notes"))
        #expect(WikiLinkURL.target(from: url) == "👩‍💻 notes")
    }

    @Test("A blank target produces no URL")
    func blankTarget() {
        #expect(WikiLinkURL.url(for: "   ") == nil)
        #expect(WikiLinkURL.url(for: "") == nil)
    }

    @Test("A foreign URL is not read as a wikilink")
    func foreignURLRejected() throws {
        let url = try #require(URL(string: "https://example.com/Memo"))
        #expect(WikiLinkURL.target(from: url) == nil)
    }

    @Test("A logue deep link is not read as a wikilink")
    func deepLinkRejected() throws {
        let url = try #require(URL(string: "logue://document/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(WikiLinkURL.target(from: url) == nil)
    }

    @Test("A wikilink URL with no target reads as nothing")
    func emptyPath() throws {
        let url = try #require(URL(string: "\(WikiLinkURL.scheme)://"))
        #expect(WikiLinkURL.target(from: url) == nil)
    }
}

/// The styler must attach a `.link` AppKit can act on — this is what makes the
/// link clickable without intercepting mouse events.
@Suite("WikiLinkLinkAttribute")
@MainActor
struct WikiLinkLinkAttributeTests {
    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler().restyleInline(
            storage,
            defaultFont: .systemFont(ofSize: 14),
            defaultParaStyle: NSMutableParagraphStyle(),
            defaultTextColor: .labelColor
        )
        return storage
    }

    @Test("A link attribute is attached over the link text")
    func linkAttached() throws {
        let storage = styled("see [[Memo]] now")
        let value = storage.attribute(.link, at: 6, effectiveRange: nil)
        let url = try #require((value as? URL) ?? (value as? String).flatMap(URL.init(string:)))
        #expect(WikiLinkURL.target(from: url) == "Memo")
    }

    @Test("Plain text gets no link attribute")
    func plainTextNoLink() {
        let storage = styled("nothing here")
        #expect(storage.attribute(.link, at: 3, effectiveRange: nil) == nil)
    }

    @Test("An aliased link's display text carries the target's URL")
    func aliasedLinkAttached() throws {
        let storage = styled("[[Memo|the memo]]")
        let value = storage.attribute(.link, at: 8, effectiveRange: nil)
        let url = try #require((value as? URL) ?? (value as? String).flatMap(URL.init(string:)))
        #expect(WikiLinkURL.target(from: url) == "Memo")
    }

    @Test("A target with spaces still produces a usable link attribute")
    func spacedTargetAttached() throws {
        let storage = styled("[[Project Alpha]]")
        let value = storage.attribute(.link, at: 3, effectiveRange: nil)
        let url = try #require((value as? URL) ?? (value as? String).flatMap(URL.init(string:)))
        #expect(WikiLinkURL.target(from: url) == "Project Alpha")
    }
}
