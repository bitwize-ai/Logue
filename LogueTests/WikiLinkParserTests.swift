import Foundation
@testable import Logue
import Testing

@Suite("WikiLinkParser")
struct WikiLinkParserTests {
    // MARK: - Basic parsing

    @Test("A single link is found with its target")
    func singleLink() {
        let links = WikiLinkParser.links(in: "See [[Project Alpha]] for detail.")
        #expect(links.count == 1)
        #expect(links.first?.target == "Project Alpha")
    }

    @Test("Multiple links are found in document order")
    func multipleLinks() {
        let links = WikiLinkParser.links(in: "[[One]] then [[Two]] then [[Three]]")
        #expect(links.map(\.target) == ["One", "Two", "Three"])
    }

    @Test("Text with no links yields nothing")
    func noLinks() {
        #expect(WikiLinkParser.links(in: "Plain prose with [single] brackets.").isEmpty)
    }

    @Test("An empty string yields nothing")
    func emptyString() {
        #expect(WikiLinkParser.links(in: "").isEmpty)
    }

    // MARK: - Aliases

    @Test("A pipe separates target from display text")
    func aliasedLink() {
        let link = WikiLinkParser.links(in: "[[Project Alpha|the alpha project]]").first
        #expect(link?.target == "Project Alpha")
        #expect(link?.displayText == "the alpha project")
    }

    @Test("Without a pipe there is no separate display text")
    func noAliasMeansNilDisplayText() {
        #expect(WikiLinkParser.links(in: "[[Target]]").first?.displayText == nil)
    }

    @Test("An empty display text is treated as absent")
    func emptyAliasIsNil() {
        let link = WikiLinkParser.links(in: "[[Target|]]").first
        #expect(link?.target == "Target")
        #expect(link?.displayText == nil)
    }

    @Test("Resolved text prefers the display text when present")
    func resolvedText() {
        #expect(WikiLinkParser.links(in: "[[A|shown]]").first?.resolvedText == "shown")
        #expect(WikiLinkParser.links(in: "[[A]]").first?.resolvedText == "A")
    }

    // MARK: - Malformed input

    @Test("An empty target is not a link")
    func emptyTargetIgnored() {
        #expect(WikiLinkParser.links(in: "[[]] and [[   ]]").isEmpty)
    }

    @Test("An unclosed link is not a link")
    func unclosedIgnored() {
        #expect(WikiLinkParser.links(in: "[[never closed").isEmpty)
    }

    @Test("Single brackets are not a link")
    func singleBracketsIgnored() {
        #expect(WikiLinkParser.links(in: "[not a wikilink]").isEmpty)
    }

    @Test("A link may not span lines")
    func linkCannotSpanLines() {
        #expect(WikiLinkParser.links(in: "[[start\nend]]").isEmpty)
    }

    @Test("Surrounding whitespace is trimmed from the target")
    func targetIsTrimmed() {
        #expect(WikiLinkParser.links(in: "[[  Spaced Out  ]]").first?.target == "Spaced Out")
    }

    // MARK: - Ranges

    @Test("The range covers the whole link including delimiters")
    func rangeCoversDelimiters() throws {
        let text = "go [[Target]] now"
        let link = try #require(WikiLinkParser.links(in: text).first)
        #expect((text as NSString).substring(with: link.range) == "[[Target]]")
    }

    /// Guardrail: ranges are UTF-16 (NSRange). A multi-UTF-16 character before the
    /// link must not shift the range, or callers styling the text corrupt it.
    @Test("Ranges stay correct with emoji before the link")
    func rangeWithLeadingEmoji() throws {
        let text = "👩‍💻 記録 [[Target]] end"
        let link = try #require(WikiLinkParser.links(in: text).first)
        #expect((text as NSString).substring(with: link.range) == "[[Target]]")
    }

    @Test("Ranges of consecutive links do not overlap")
    func consecutiveRangesDoNotOverlap() {
        let links = WikiLinkParser.links(in: "[[A]][[B]]")
        #expect(links.count == 2)
        #expect(NSMaxRange(links[0].range) <= links[1].range.location)
    }

    // MARK: - Unicode targets

    @Test("A unicode target is preserved exactly")
    func unicodeTarget() {
        #expect(WikiLinkParser.links(in: "[[会議メモ]]").first?.target == "会議メモ")
    }

    // MARK: - Targets collection

    @Test("Unique targets are reported once, case-insensitively")
    func uniqueTargets() {
        let targets = WikiLinkParser.uniqueTargets(in: "[[Alpha]] [[alpha]] [[Beta]]")
        #expect(targets.count == 2)
    }

    @Test("Unique targets of link-free text is empty")
    func uniqueTargetsEmpty() {
        #expect(WikiLinkParser.uniqueTargets(in: "nothing here").isEmpty)
    }
}
