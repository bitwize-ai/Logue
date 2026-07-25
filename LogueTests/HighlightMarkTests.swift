import Foundation
@testable import Logue
import Testing

/// `==highlight==` is a non-CommonMark inline mark. The block serializer must
/// carry it through a markdown round trip untouched, otherwise applying a
/// highlight and reopening the document silently loses it.
@Suite("HighlightMark")
struct HighlightMarkTests {
    @Test("Highlight syntax survives a markdown round trip")
    func roundTrip() {
        let markdown = "Some ==important== text"
        let blocks = BlockSerializer.parse(markdown: markdown)
        let output = BlockSerializer.serialize(blocks: blocks)

        #expect(output.contains("==important=="))
    }

    @Test("Toggling highlight on plain text wraps it")
    func togglingWrapsPlainText() {
        let result = HighlightMark.toggled(in: "make this bold", range: NSRange(location: 5, length: 4))
        #expect(result == "make ==this== bold")
    }

    @Test("Toggling highlight on already-highlighted text unwraps it")
    func togglingUnwrapsHighlightedText() {
        let text = "make ==this== bold"
        // Range covers "this" inside the existing delimiters.
        let result = HighlightMark.toggled(in: text, range: NSRange(location: 7, length: 4))
        #expect(result == "make this bold")
    }

    @Test("Toggling an empty selection leaves the text unchanged")
    func emptySelectionIsNoOp() {
        let result = HighlightMark.toggled(in: "unchanged", range: NSRange(location: 3, length: 0))
        #expect(result == "unchanged")
    }

    @Test("A range beyond the text length leaves the text unchanged")
    func outOfBoundsRangeIsNoOp() {
        let result = HighlightMark.toggled(in: "short", range: NSRange(location: 2, length: 99))
        #expect(result == "short")
    }

    @Test("Highlighted ranges are detected for styling")
    func detectsRangesForStyling() {
        let ranges = HighlightMark.ranges(in: "a ==one== b ==two== c")
        #expect(ranges.count == 2)
    }

    @Test("Unpaired delimiters produce no highlight ranges")
    func unpairedDelimiterIsNotAHighlight() {
        #expect(HighlightMark.ranges(in: "a == b").isEmpty)
    }
}
