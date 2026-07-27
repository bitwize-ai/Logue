import AppKit
@testable import Logue
import Testing

/// Hit-testing a wikilink in a laid-out text view — the step between styling and
/// navigation, and the one that was failing in the app.
@Suite("WikiLinkClick")
@MainActor
struct WikiLinkClickTests {
    /// A laid-out text view containing `text`, styled the way the editor styles it.
    private func textView(_ text: String) -> BlockNSTextView {
        let view = BlockNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.markdownStyleEnabled = true
        view.baseFont = .systemFont(ofSize: 14)
        view.font = view.baseFont
        view.string = text

        if let storage = view.textStorage {
            view.markdownStyler.restyleInline(
                storage,
                defaultFont: view.baseFont,
                defaultParaStyle: NSMutableParagraphStyle(),
                defaultTextColor: .labelColor
            )
        }
        view.layoutManager?.ensureLayout(for: view.textContainer ?? NSTextContainer())
        return view
    }

    /// A point at the centre of the glyphs for `substring`.
    private func centrePoint(
        of substring: String,
        in view: BlockNSTextView
    ) -> NSPoint? {
        guard let layoutManager = view.layoutManager,
              let container = view.textContainer
        else { return nil }

        let range = (view.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
    }

    @Test("Clicking the middle of a link finds its target")
    func middleOfLink() throws {
        let view = textView("see [[Memo]] now")
        let point = try #require(centrePoint(of: "Memo", in: view))
        #expect(view.wikiLinkTarget(at: point) == "Memo")
    }

    /// This is the case that failed in the app: the nearest-insertion-point lookup
    /// rounded past the final character into the hidden `]]`.
    @Test("Clicking the last character of a link still finds its target")
    func lastCharacterOfLink() throws {
        let view = textView("see [[Memo]] now")
        let point = try #require(centrePoint(of: "o", in: view))
        #expect(view.wikiLinkTarget(at: point) == "Memo")
    }

    @Test("Clicking outside a link finds nothing")
    func outsideLink() throws {
        let view = textView("see [[Memo]] now")
        let point = try #require(centrePoint(of: "see", in: view))
        #expect(view.wikiLinkTarget(at: point) == nil)
    }

    @Test("Clicking plain text with no links finds nothing")
    func plainText() throws {
        let view = textView("nothing to see here")
        let point = try #require(centrePoint(of: "nothing", in: view))
        #expect(view.wikiLinkTarget(at: point) == nil)
    }

    @Test("An aliased link resolves on its target from the display text")
    func aliasedLink() throws {
        let view = textView("[[Memo|the memo]]")
        let point = try #require(centrePoint(of: "the memo", in: view))
        #expect(view.wikiLinkTarget(at: point) == "Memo")
    }

    @Test("Each of two links resolves to its own target")
    func twoLinks() throws {
        let view = textView("[[One]] and [[Two]]")
        let first = try #require(centrePoint(of: "One", in: view))
        let second = try #require(centrePoint(of: "Two", in: view))
        #expect(view.wikiLinkTarget(at: first) == "One")
        #expect(view.wikiLinkTarget(at: second) == "Two")
    }

    @Test("An empty text view is safe to hit-test")
    func emptyView() {
        let view = textView("")
        #expect(view.wikiLinkTarget(at: NSPoint(x: 5, y: 5)) == nil)
    }

    @Test("A point far outside the text is safe to hit-test")
    func farOutsidePoint() {
        let view = textView("[[Memo]]")
        #expect(view.wikiLinkTarget(at: NSPoint(x: 9999, y: 9999)) == nil)
    }
}
