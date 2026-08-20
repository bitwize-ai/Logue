import CoreGraphics

/// How many "Continue where you left off" cards fit, and therefore how many to keep.
///
/// The cap is the whole point of the section: two rows leave Quick Actions and the Daily
/// Digest above the fold. Three rows push them below it, which is what a horizontal
/// carousel was doing differently and worse. That makes the arithmetic worth testing
/// rather than burying in a private computed property on a `View`, where an off-by-one
/// between `width` and `width + spacing` grows a third row at one specific window width
/// and nothing catches it — the same reason `SidebarWidthLimit` is its own type.
enum HomeContinueGrid {
    /// Narrowest a card may get before the grid drops to fewer columns.
    static let minCardWidth: CGFloat = 200
    static let spacing: CGFloat = 12
    static let maxRows = 2

    /// Columns that fit in `width`, never fewer than one — a single column that overflows
    /// slightly still beats rendering nothing.
    static func columnCount(forWidth width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        // Each column costs its own width plus one gap; the row has one fewer gap than
        // columns, so lend it a gap on both sides of the division.
        let usable = width + spacing
        let perCard = minCardWidth + spacing
        return max(1, Int(usable / perCard))
    }

    /// The most cards that can show at `width` without exceeding `maxRows`.
    static func maximumItems(forWidth width: CGFloat) -> Int {
        columnCount(forWidth: width) * maxRows
    }

    /// How many items the section asks the stores for.
    ///
    /// Fetching fewer than `maximumItems` at the widest layout would leave a hole in the
    /// second row, so this must stay equal to the maximum at the full content column —
    /// `HomeContinueGridTests` asserts exactly that, because the two numbers live in
    /// different files and nothing else ties them together.
    static var fetchLimit: Int {
        maximumItems(forWidth: AppThemeConstants.contentColumnWidth)
    }
}
