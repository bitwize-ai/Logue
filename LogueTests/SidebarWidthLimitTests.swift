import Foundation
@testable import Logue
import Testing

/// How far a sidebar may be dragged. The property worth guarding is that the content
/// pane keeps its reading measure: a panel that can be dragged until the editor scrolls
/// sideways is the bug this rule exists to prevent.
@Suite("SidebarWidthLimit")
struct SidebarWidthLimitTests {
    private static let limits: [(name: String, limit: SidebarWidthLimit)] = [
        ("categorySidebar", .categorySidebar),
        ("inspector", .inspector),
        ("libraryPanel", .libraryPanel),
    ]

    // MARK: - The library panel

    /// The library panels sit beside a list, not an editor, so they are not held to the
    /// editor's reading measure — which on a normal window capped them barely above their
    /// own default width.
    @Test("A library panel may be dragged far wider than an inspector")
    func libraryPanelOutgrowsTheInspector() {
        let window: CGFloat = 1280
        let inspector = SidebarWidthLimit.inspector.maximum(inContainerOfWidth: window)
        let library = SidebarWidthLimit.libraryPanel.maximum(inContainerOfWidth: window)
        #expect(library > inspector * 1.5)
    }

    @Test("A library panel still leaves the list something to be")
    func libraryPanelLeavesRoomForTheList() {
        for window in [900, 1280, 1600, 2560].map(CGFloat.init) {
            let maximum = SidebarWidthLimit.libraryPanel.maximum(inContainerOfWidth: window)
            #expect(window - maximum >= SidebarWidthLimit.libraryPanel.minContentWidth
                || maximum == SidebarWidthLimit.libraryPanel.minimum)
        }
    }

    // MARK: - The two limits

    @Test("A large container is bounded by the ceiling, not by the window")
    func ceilingWinsInALargeWindow() {
        for (name, limit) in Self.limits {
            #expect(limit.maximum(inContainerOfWidth: 3440) == limit.ceiling, "\(name)")
            #expect(limit.maximum(inContainerOfWidth: 5120) == limit.ceiling, "\(name)")
        }
    }

    @Test("A small container is bounded by what it can spare, not by the ceiling")
    func windowWinsInASmallWindow() {
        // 1000 wide leaves 280 once the content keeps its 720 measure — under either ceiling.
        #expect(SidebarWidthLimit.inspector.maximum(inContainerOfWidth: 1000) == 280)
        #expect(SidebarWidthLimit.categorySidebar.maximum(inContainerOfWidth: 1000) == 280)
    }

    @Test("The content pane keeps its reading measure wherever the window allows it")
    func contentKeepsItsReadingMeasure() {
        for (name, limit) in Self.limits {
            for containerWidth in stride(from: CGFloat(1000), through: 4000, by: 20) {
                let contentLeft = containerWidth - limit.maximum(inContainerOfWidth: containerWidth)
                #expect(contentLeft >= limit.minContentWidth, "\(name) at container \(containerWidth)")
            }
        }
    }

    /// A window too small to give the content its measure cannot also honour it. The
    /// sidebar's own minimum wins there, because a panel narrower than its content can
    /// show is useless in a way a slightly squeezed editor is not.
    @Test("In a window too small for both, the sidebar keeps its own minimum")
    func sidebarMinimumWinsInATinyWindow() {
        for (name, limit) in Self.limits {
            #expect(limit.maximum(inContainerOfWidth: 600) == limit.minimum, "\(name)")
            #expect(limit.maximum(inContainerOfWidth: 300) == limit.minimum, "\(name)")
        }
    }

    @Test("An unmeasured container applies only the ceiling")
    func unmeasuredContainerAppliesOnlyTheCeiling() {
        for (name, limit) in Self.limits {
            #expect(limit.maximum(inContainerOfWidth: 0) == limit.ceiling, "\(name)")
        }
    }

    @Test("Widening the container never narrows the limit")
    func limitIsMonotonic() {
        for (name, limit) in Self.limits {
            var previous: CGFloat = 0
            for containerWidth in stride(from: CGFloat(300), through: 4000, by: 20) {
                let maximum = limit.maximum(inContainerOfWidth: containerWidth)
                #expect(maximum >= previous, "\(name) narrowed at container \(containerWidth)")
                previous = maximum
            }
        }
    }

    // MARK: - Clamping

    @Test("Clamping brings a width inside both limits")
    func clampingRespectsBothLimits() {
        let inspector = SidebarWidthLimit.inspector
        // Too wide for the ceiling.
        #expect(inspector.clamping(2000, inContainerOfWidth: 3440) == inspector.ceiling)
        // Too wide for the window.
        #expect(inspector.clamping(2000, inContainerOfWidth: 1000) == 280)
        // Too narrow for the sidebar itself.
        #expect(inspector.clamping(50, inContainerOfWidth: 1600) == inspector.minimum)
        // Already fine.
        #expect(inspector.clamping(400, inContainerOfWidth: 1600) == 400)
    }

    /// Shrinking the window must narrow the panel on screen without the stored width
    /// being lost — grow the window back and the chosen width returns.
    @Test("A width kept through a shrink is restored when the container grows back")
    func chosenWidthSurvivesAShrink() {
        let inspector = SidebarWidthLimit.inspector
        let chosen: CGFloat = 700

        #expect(inspector.clamping(chosen, inContainerOfWidth: 1200) == 480)
        #expect(inspector.clamping(chosen, inContainerOfWidth: 1600) == chosen)
    }

    // MARK: - The presets

    @Test("The inspector may be dragged wider than the navigation column")
    func inspectorOutranksTheNavigationColumn() {
        #expect(SidebarWidthLimit.inspector.ceiling > SidebarWidthLimit.categorySidebar.ceiling)
    }

    @Test("Every preset is internally consistent")
    func presetsAreConsistent() {
        for (name, limit) in Self.limits {
            #expect(limit.minimum > 0, "\(name)")
            #expect(limit.ceiling > limit.minimum, "\(name)")
            #expect(limit.minContentWidth > 0, "\(name)")
        }
    }
}
