import CoreGraphics
@testable import Logue
import Testing

/// How many Continue cards fit. The property worth guarding is the row cap: a third row
/// pushes Quick Actions and the Daily Digest below the fold, which is the failure the
/// wrapping grid replaced a carousel to avoid.
@Suite("HomeContinueGrid")
struct HomeContinueGridTests {
    @Test("Every column fits a whole card, at every width")
    func columnsAlwaysFitTheirCards() {
        // The row cap cannot be checked against `maximumItems`, which is *defined* as
        // `columnCount * maxRows` — that arithmetic holds for any `columnCount` at all, so
        // replacing it with `{ _ in 47 }` passed at every sampled width. What actually decides
        // whether a third row appears is that a column is never narrower than a card: too many
        // columns and the grid wraps.
        for width in stride(from: CGFloat(200), through: 3000, by: 4) {
            let columns = CGFloat(HomeContinueGrid.columnCount(forWidth: width))
            let needed = columns * HomeContinueGrid.minCardWidth
                + (columns - 1) * HomeContinueGrid.spacing
            #expect(needed <= width, "\(Int(columns)) columns do not fit in \(width)pt")
        }
    }

    @Test("The fetch limit is the column count times the row cap")
    func maximumItemsMultipliesColumnsByTheRowCap() {
        // Named for what it actually pins. It restates `maximumItems`'s definition, so it
        // detects only someone decoupling it from `maxRows` — replace `columnCount` with a
        // constant and both sides still agree. The row cap itself is held by
        // `columnsAlwaysFitTheirCards` and by `fetchLimitIsSix`; this is not a third witness.
        for width in stride(from: CGFloat(200), through: 3000, by: 4) {
            let items = HomeContinueGrid.maximumItems(forWidth: width)
            let columns = HomeContinueGrid.columnCount(forWidth: width)
            #expect(items == columns * HomeContinueGrid.maxRows, "at width \(width)")
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

    @Test("The fetch limit is six: three columns, two rows")
    func fetchLimitIsSix() {
        // Written out rather than derived. `fetchLimit` *is*
        // `maximumItems(forWidth: contentColumnWidth)`, so comparing the two was `x == x` and
        // held however either side changed. Six is what the design was drawn against, and
        // retuning the content column or the minimum card width has to come past this line.
        #expect(HomeContinueGrid.fetchLimit == 6)
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
