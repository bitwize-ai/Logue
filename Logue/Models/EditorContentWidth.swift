import CoreGraphics

/// How wide the editor's text column should be inside a pane of a given width.
///
/// The column is measured separately from the scroll view that holds it: the scroll
/// view fills the pane, so its scroller sits at the pane's right edge, and only the
/// blocks inside are constrained to this width and centred. Constraining the scroll
/// view itself is what used to park the scroller mid-window.
///
/// Pure by design — the whole rule is one function of pane width, so it is tested
/// directly rather than through a view.
enum EditorContentWidth: Equatable, Sendable {
    /// A column the window does not get a say in. Focus mode sets its own measure.
    case fixed(CGFloat)
    /// A column that grows with the pane, within the mode's base measure and ceiling.
    case scaling(DocumentWidthMode)

    /// The column width to use in a pane this wide.
    ///
    /// For a scaling column: a share of the pane, but never narrower than the mode's
    /// base measure (so a laptop-width window is no worse off than before the column
    /// could grow), never wider than its ceiling, and never wider than the pane.
    func resolved(forPaneWidth paneWidth: CGFloat) -> CGFloat {
        // A pane can measure zero — or briefly negative — during window setup and
        // sidebar animations; a negative frame width traps in SwiftUI.
        let pane = max(0, paneWidth)

        switch self {
        case let .fixed(width):
            return min(width, pane)
        case let .scaling(mode):
            let grown = max(pane * mode.widthFraction, min(pane, mode.baseContentWidth))
            return min(grown, mode.maxContentWidth, pane)
        }
    }
}
