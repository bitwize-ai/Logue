import Foundation
@testable import Logue
import Testing

/// The rule that decides how wide the editor's text column is for a given pane.
///
/// The property that matters most here is the one in `neverNarrowerThanTheBaseMeasure`:
/// scaling by a fraction alone would have made a laptop-width window *narrower* than it
/// was before the column could grow at all, which is a regression dressed up as a feature.
@Suite("EditorContentWidth")
struct EditorContentWidthTests {
    // MARK: - Growth

    @Test(
        "Normal grows with the pane once the fraction beats the base measure",
        arguments: [
            (paneWidth: CGFloat(1100), expected: CGFloat(770)),
            (paneWidth: CGFloat(1200), expected: CGFloat(840)),
            (paneWidth: CGFloat(1280), expected: CGFloat(896)),
        ]
    )
    func normalGrowsWithPane(paneWidth: CGFloat, expected: CGFloat) {
        #expect(EditorContentWidth.scaling(.normal).resolved(forPaneWidth: paneWidth) == expected)
    }

    @Test(
        "Wide grows with the pane once the fraction beats the base measure",
        arguments: [
            (paneWidth: CGFloat(1300), expected: CGFloat(1170)),
            (paneWidth: CGFloat(1500), expected: CGFloat(1350)),
        ]
    )
    func wideGrowsWithPane(paneWidth: CGFloat, expected: CGFloat) {
        #expect(EditorContentWidth.scaling(.wide).resolved(forPaneWidth: paneWidth) == expected)
    }

    // MARK: - Ceilings

    @Test("Each mode stops growing at its ceiling", arguments: [CGFloat(1800), 2400, 5000])
    func ceilingsHold(paneWidth: CGFloat) {
        #expect(
            EditorContentWidth.scaling(.normal).resolved(forPaneWidth: paneWidth)
                == AppConstants.Editor.normalMaxContentWidth
        )
        #expect(
            EditorContentWidth.scaling(.wide).resolved(forPaneWidth: paneWidth)
                == AppConstants.Editor.wideMaxContentWidth
        )
    }

    // MARK: - Floor

    /// Before the column could grow, the width was `min(pane, base)`. Nothing about
    /// making it grow may make it smaller than that at any pane width.
    @Test("Never narrower than the base measure the editor used before", arguments: [CGFloat(400), 600, 720, 900, 1000, 1400, 2000])
    func neverNarrowerThanTheBaseMeasure(paneWidth: CGFloat) {
        for mode in DocumentWidthMode.allCases {
            let previous = min(paneWidth, mode.baseContentWidth)
            #expect(EditorContentWidth.scaling(mode).resolved(forPaneWidth: paneWidth) >= previous)
        }
    }

    @Test("Never wider than the pane it has to fit in", arguments: [CGFloat(200), 400, 600, 800, 1000, 1600, 3000])
    func neverWiderThanThePane(paneWidth: CGFloat) {
        for mode in DocumentWidthMode.allCases {
            #expect(EditorContentWidth.scaling(mode).resolved(forPaneWidth: paneWidth) <= paneWidth)
        }
        #expect(EditorContentWidth.fixed(720).resolved(forPaneWidth: paneWidth) <= paneWidth)
    }

    @Test("Widening the pane never narrows the column")
    func growthIsMonotonic() {
        for mode in DocumentWidthMode.allCases {
            var previous: CGFloat = 0
            for paneWidth in stride(from: CGFloat(200), through: 3000, by: 20) {
                let width = EditorContentWidth.scaling(mode).resolved(forPaneWidth: paneWidth)
                #expect(width >= previous, "\(mode) narrowed at pane \(paneWidth)")
                previous = width
            }
        }
    }

    @Test("Wide is never narrower than normal at the same pane width", arguments: [CGFloat(400), 800, 1200, 1600, 2400])
    func wideIsNeverNarrowerThanNormal(paneWidth: CGFloat) {
        #expect(
            EditorContentWidth.scaling(.wide).resolved(forPaneWidth: paneWidth)
                >= EditorContentWidth.scaling(.normal).resolved(forPaneWidth: paneWidth)
        )
    }

    // MARK: - Fixed

    /// Focus mode sets its own column and must not scale with the window.
    @Test("A fixed column ignores the pane until the pane is smaller than it")
    func fixedColumnIgnoresPane() {
        #expect(EditorContentWidth.fixed(720).resolved(forPaneWidth: 2400) == 720)
        #expect(EditorContentWidth.fixed(720).resolved(forPaneWidth: 900) == 720)
        #expect(EditorContentWidth.fixed(720).resolved(forPaneWidth: 500) == 500)
    }

    // MARK: - Degenerate panes

    /// A pane can measure zero for a frame during window setup or a sidebar animation.
    @Test("A zero or negative pane resolves to zero rather than a negative width")
    func degeneratePaneIsClamped() {
        #expect(EditorContentWidth.scaling(.normal).resolved(forPaneWidth: 0) == 0)
        #expect(EditorContentWidth.scaling(.wide).resolved(forPaneWidth: -50) == 0)
        #expect(EditorContentWidth.fixed(720).resolved(forPaneWidth: -1) == 0)
    }
}
