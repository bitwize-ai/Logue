import CoreGraphics
@testable import Logue
import Testing

/// How many Continue cards fit. The property worth guarding is the row cap: a third row
/// pushes Quick Actions and the Daily Digest below the fold, which is the failure the
/// wrapping grid replaced a carousel to avoid.
@Suite("HomeContinueGrid")
struct HomeContinueGridTests {
    @Test("Two rows, at every width")
    func neverExceedsTwoRows() {
        // Every width from a very narrow pane to an ultrawide display.
        for width in stride(from: CGFloat(120), through: 3000, by: 4) {
            let columns = HomeContinueGrid.columnCount(forWidth: width)
            let items = HomeContinueGrid.maximumItems(forWidth: width)
            let rows = Int((Double(items) / Double(columns)).rounded(.up))
            #expect(rows <= HomeContinueGrid.maxRows, "at width \(width)")
        }
    }

    @Test("Always at least one column, even at implausible widths")
    func alwaysAtLeastOneColumn() {
        for width in [CGFloat(0), 1, 10, 199] {
            #expect(HomeContinueGrid.columnCount(forWidth: width) >= 1, "at width \(width)")
        }
    }

    @Test("Columns only ever grow with width")
    func columnsAreMonotonic() {
        var previous = HomeContinueGrid.columnCount(forWidth: 0)
        for width in stride(from: CGFloat(0), through: 3000, by: 2) {
            let columns = HomeContinueGrid.columnCount(forWidth: width)
            #expect(columns >= previous, "went backwards at width \(width)")
            previous = columns
        }
    }

    @Test("A column's worth of width buys exactly one more column")
    func widthBuysColumnsAtTheExpectedRate() {
        // Three cards plus the two gaps between them is exactly three columns — the
        // boundary an off-by-one on the spacing lends would get wrong.
        let exactlyThree = HomeContinueGrid.minCardWidth * 3 + HomeContinueGrid.spacing * 2
        #expect(HomeContinueGrid.columnCount(forWidth: exactlyThree) == 3)
        #expect(HomeContinueGrid.columnCount(forWidth: exactlyThree - 1) == 2)
    }

    @Test("The fetch limit fills both rows at the full content column")
    func fetchLimitFillsTheWidestLayout() {
        // These two numbers live in different files; nothing but this ties them together.
        #expect(
            HomeContinueGrid.fetchLimit
                == HomeContinueGrid.maximumItems(forWidth: AppThemeConstants.contentColumnWidth)
        )
        #expect(HomeContinueGrid.fetchLimit >= HomeContinueGrid.maxRows)
    }

    @Test("The content column fits three columns")
    func contentColumnFitsThree() {
        // Guards the layout the design was drawn against: if the column width or the
        // minimum card width is retuned, this is where that shows up.
        #expect(
            HomeContinueGrid.columnCount(forWidth: AppThemeConstants.contentColumnWidth) == 3
        )
    }
}
