import AppKit
@testable import Logue
import Testing

/// The styling pass must attach the target attribute a Command-click reads, and
/// hide the brackets. Without this the link renders raw and clicks find nothing.
@Suite("WikiLinkStyling")
@MainActor
struct WikiLinkStylingTests {
    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let styler = MarkdownStyler()
        styler.restyleInline(
            storage,
            defaultFont: .systemFont(ofSize: 14),
            defaultParaStyle: NSMutableParagraphStyle(),
            defaultTextColor: .labelColor
        )
        return storage
    }

    private func target(in storage: NSTextStorage, at index: Int) -> String? {
        storage.attribute(
            MarkdownStyler.wikiLinkTargetAttribute, at: index, effectiveRange: nil
        ) as? String
    }

    @Test("The target attribute is attached across the link text")
    func attributeAttached() {
        let storage = styled("see [[Memo]] now")
        // "[[Memo]]" starts at 4, so the inner text spans 6..<10.
        #expect(target(in: storage, at: 6) == "Memo")
        #expect(target(in: storage, at: 9) == "Memo")
    }

    @Test("Plain text carries no target attribute")
    func plainTextHasNoAttribute() {
        let storage = styled("just words here")
        #expect(target(in: storage, at: 3) == nil)
    }

    @Test("The brackets are hidden, not shown raw")
    func bracketsHidden() {
        let storage = styled("[[Memo]]")
        let colour = storage.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? NSColor
        #expect(colour == NSColor.clear)
    }

    @Test("The link text is coloured as a link")
    func linkTextColoured() {
        let storage = styled("[[Memo]]")
        let colour = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(colour != NSColor.labelColor)
        #expect(colour != NSColor.clear)
    }

    @Test("An aliased link attaches the target, not the display text")
    func aliasAttachesTarget() {
        let storage = styled("[[Memo|the memo]]")
        // Display text begins after "[[Memo|" — index 7.
        #expect(target(in: storage, at: 8) == "Memo")
    }

    @Test("Two links each carry their own target")
    func twoLinks() {
        let storage = styled("[[One]] and [[Two]]")
        #expect(target(in: storage, at: 3) == "One")
        #expect(target(in: storage, at: 15) == "Two")
    }

    @Test("A target attribute survives an emoji earlier in the text")
    func attributeSurvivesEmoji() {
        let text = "👩‍💻 [[Memo]]"
        let storage = styled(text)
        let linkStart = (text as NSString).range(of: "Memo").location
        #expect(target(in: storage, at: linkStart) == "Memo")
    }

    @Test("An unclosed link attaches nothing")
    func unclosedAttachesNothing() {
        let storage = styled("[[Memo")
        #expect(target(in: storage, at: 3) == nil)
    }
}

/// The delimiter list `deleteBackward` deletes through, and the range arithmetic behind the
/// hidden `Target|` of an aliased link.
///
/// Both were found by review. The parity one is the worst bug in the feature: one Backspace
/// silently rewrote a *different* link and the change was persisted.
@Suite("WikiLink delimiter pairing")
@MainActor
struct WikiLinkDelimiterPairingTests {
    private func styler(for text: String) -> MarkdownStyler {
        let storage = NSTextStorage(string: text)
        let styler = MarkdownStyler()
        styler.restyleInline(
            storage,
            defaultFont: .systemFont(ofSize: 14),
            defaultParaStyle: NSMutableParagraphStyle(),
            defaultTextColor: .labelColor
        )
        return styler
    }

    /// `pairedDelimiter` pairs by `idx % 2`, so an aliased link contributing a third range flipped
    /// the parity of every delimiter after it.
    @Test("Every link contributes exactly two delimiter ranges, aliased or not")
    func twoRangesPerLink() {
        #expect(styler(for: "[[A]]").delimiterRanges.count == 2)
        #expect(styler(for: "[[A|a]]").delimiterRanges.count == 2)
        #expect(styler(for: "[[A|a]] [[B]]").delimiterRanges.count == 4)
    }

    /// The reviewer's repro: caret after the `[[` of `[[B]]`, Backspace. With the parity broken,
    /// the opening of `[[B]]` paired with the *closing* of `[[A|a]]`, so the deletion spanned two
    /// links and rewrote the first one.
    @Test("An aliased link does not misalign the pairing of a later link")
    func aliasDoesNotBreakLaterPairing() throws {
        let styler = styler(for: "[[A|a]] [[B]]")

        // `[[B]]` opens at offset 8 and closes at 11.
        let opening = try #require(styler.delimiterRange(containing: 8))
        let paired = try #require(styler.pairedDelimiter(for: opening))

        #expect(paired.location == 11)
        #expect(NSMaxRange(paired) == 13)
    }

    @Test("A plain link's delimiters pair with each other")
    func plainLinkPairs() throws {
        let styler = styler(for: "see [[Memo]] now")

        let opening = try #require(styler.delimiterRange(containing: 4))
        let paired = try #require(styler.pairedDelimiter(for: opening))

        #expect(paired.location == 10)
    }

    /// `String.distance` counted `Character`s where an `NSRange.length` was needed, so anything
    /// multi-unit before the pipe left the raw target visible and split a surrogate pair.
    @Test("The hidden span of an aliased link reaches the pipe, whatever is before it")
    func aliasHiddenSpanIsMeasuredInUTF16() throws {
        // Plain ASCII: `[[` plus `Alpha|` is 8 UTF-16 units.
        let ascii = styler(for: "[[Alpha|first]]")
        #expect(try #require(ascii.delimiterRanges.first).length == 8)

        // An emoji target is one `Character` but two UTF-16 units.
        let emoji = styler(for: "[[\u{1F600}A|alias]]")
        #expect(try #require(emoji.delimiterRanges.first).length == 6)

        // A ZWJ family is one `Character` and eleven UTF-16 units.
        let family = styler(for: "[[\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}|Family]]")
        #expect(try #require(family.delimiterRanges.first).length == 11)
    }

    /// The consequence of getting that length wrong: the target and pipe stay on screen.
    @Test("An emoji target does not leave the pipe visible")
    func emojiTargetHidesThePipe() throws {
        let styler = styler(for: "[[\u{1F600}A|alias]]")
        let hidden = try #require(styler.delimiterRanges.first)

        // The hidden span ends immediately after the pipe, so `alias` is what remains.
        #expect(NSMaxRange(hidden) == 6)
    }
}
