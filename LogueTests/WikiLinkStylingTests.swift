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
