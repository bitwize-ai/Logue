import Foundation
@testable import Logue
import Testing

/// The two shapes where callout markdown does **not** come back byte-for-byte, pinned so the
/// behaviour is a decision rather than a surprise.
///
/// This matters more than it looks: in markdown storage mode the file *is* the document, so any
/// difference between what was read and what is written is the app rewriting the user's file the
/// first time they open it. `CalloutBlockTests` covers everything that is exact; these are the
/// exceptions, and each is checked against the plain-block-quote behaviour it inherits so a
/// future reader can see which half is ours.
@Suite("CalloutRoundTripEdges")
struct CalloutRoundTripEdgeTests {
    private func roundTrip(_ markdown: String) -> String {
        BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown))
    }

    // MARK: - Lazy continuation

    /// CommonMark lazy continuation: the unquoted line belongs to the quote, and ending the
    /// callout at the last `>` separates it rather than absorbing it.
    @Test("An unquoted line after a callout is separated by a blank line")
    func unquotedLineAfterCalloutGainsABlankLine() {
        #expect(roundTrip("> [!NOTE]\n> Body\nRegular paragraph")
            == "> [!NOTE]\n> Body\n\nRegular paragraph")
    }

    /// The separation is the point: both blocks survive. What this replaced was cmark folding
    /// the callout and the paragraph into one quote, which lost the paragraph as a block.
    @Test("Separating it keeps both blocks, which is why it is preferred to folding")
    func lazyContinuationKeepsBothBlocks() {
        let blocks = BlockSerializer.parse(markdown: "> [!NOTE]\n> Body\nRegular paragraph")

        #expect(blocks.count == 2)
        guard case let .callout(_, kind, _, body) = blocks[0] else {
            Issue.record("Expected a callout first, got \(blocks[0])")
            return
        }
        #expect(kind == .note)
        #expect(body == "Body")
        guard case let .paragraph(_, text) = blocks[1] else {
            Issue.record("Expected a paragraph second, got \(blocks[1])")
            return
        }
        #expect(text == "Regular paragraph")
    }

    /// Written with the blank line already there, it is exact — so the rewrite happens once and
    /// is stable, rather than growing a line on every save.
    @Test("The separated form is stable on a second pass")
    func lazyContinuationIsIdempotent() {
        let once = roundTrip("> [!NOTE]\n> Body\nRegular paragraph")
        #expect(roundTrip(once) == once)
    }

    // MARK: - Unrecognised types

    /// Inherited from block quotes rather than introduced here — see the baseline below.
    @Test("An unrecognised type folds its line breaks")
    func unrecognisedTypeFoldsLineBreaks() {
        #expect(roundTrip("> [!BANANA]\n> Body") == "> [!BANANA] Body")
    }

    /// The baseline that proves the fold above is not ours: a plain multi-line quote does the
    /// same thing, and did before callouts existed.
    @Test("A plain multi-line quote folds the same way")
    func plainQuoteFoldsTheSameWay() {
        #expect(roundTrip("> One\n> Two") == "> One Two")
        #expect(roundTrip("> Quoted\nRegular paragraph") == "> Quoted Regular paragraph")
    }

    /// The marker survives the fold, so nothing the user typed is dropped — it just stops being
    /// a separate line.
    @Test("An unrecognised marker is preserved, not discarded")
    func unrecognisedMarkerSurvives() {
        let output = roundTrip("> [!BANANA]\n> Body")
        #expect(output.contains("[!BANANA]"))
        #expect(output.contains("Body"))
    }

    // MARK: - Shapes that are exact, kept here as the boundary

    /// With the blank line present the callout and the paragraph are both exact — this is the
    /// shape the editor itself writes, so normal editing never hits the rewrite above.
    @Test("A blank line between a callout and a paragraph round-trips exactly")
    func blankLineSeparatedIsExact() {
        let markdown = "> [!NOTE]\n> Body\n\nRegular paragraph"
        #expect(roundTrip(markdown) == markdown)
    }

    /// Verified in review: a nested quote inside a callout body survives intact, because body
    /// lines are taken verbatim after one `>` and a single space.
    @Test("A nested quote inside a callout round-trips exactly")
    func nestedQuoteIsExact() {
        let markdown = "> [!NOTE]\n> > inner\n> after"
        #expect(roundTrip(markdown) == markdown)
    }

    /// Also verified in review: indentation inside the body is the author's, and only the one
    /// separator space after `>` is removed.
    @Test("An indented body line keeps its indentation")
    func indentedBodyIsExact() {
        let markdown = "> [!TIP]\n>     indented code-ish\n> plain"
        #expect(roundTrip(markdown) == markdown)
    }
}
