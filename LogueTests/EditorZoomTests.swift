import Foundation
@testable import Logue
import Testing

@Suite("EditorZoom")
struct EditorZoomTests {
    @Test("Zoom starts at 100 percent")
    func startsAtDefault() {
        #expect(EditorZoom().scale == AppConstants.Editor.defaultZoom)
    }

    @Test("Zooming in raises the scale by one step")
    func zoomInRaisesScale() {
        var zoom = EditorZoom()
        zoom.zoomIn()
        #expect(zoom.scale > AppConstants.Editor.defaultZoom)
    }

    @Test("Zooming out lowers the scale by one step")
    func zoomOutLowersScale() {
        var zoom = EditorZoom()
        zoom.zoomOut()
        #expect(zoom.scale < AppConstants.Editor.defaultZoom)
    }

    @Test("Zoom never exceeds the maximum no matter how often it is raised")
    func clampsAtMaximum() {
        var zoom = EditorZoom()
        for _ in 0 ..< 200 { zoom.zoomIn() }
        #expect(zoom.scale == AppConstants.Editor.maxZoom)
    }

    @Test("Zoom never falls below the minimum no matter how often it is lowered")
    func clampsAtMinimum() {
        var zoom = EditorZoom()
        for _ in 0 ..< 200 { zoom.zoomOut() }
        #expect(zoom.scale == AppConstants.Editor.minZoom)
    }

    @Test("Resetting returns to 100 percent")
    func resetReturnsToDefault() {
        var zoom = EditorZoom()
        zoom.zoomIn()
        zoom.zoomIn()
        zoom.reset()
        #expect(zoom.scale == AppConstants.Editor.defaultZoom)
    }

    @Test("An out-of-range scale is clamped on assignment")
    func assignmentIsClamped() {
        var zoom = EditorZoom()
        zoom.scale = 99
        #expect(zoom.scale == AppConstants.Editor.maxZoom)
        zoom.scale = -5
        #expect(zoom.scale == AppConstants.Editor.minZoom)
    }

    @Test("Scaling a font size multiplies by the current scale")
    func scalesFontSize() {
        var zoom = EditorZoom()
        zoom.scale = 2.0
        #expect(zoom.scaled(16) == 32)
    }

    @Test("Zoom in then out returns to the starting scale")
    func inThenOutIsSymmetric() {
        var zoom = EditorZoom()
        zoom.zoomIn()
        zoom.zoomOut()
        #expect(abs(zoom.scale - AppConstants.Editor.defaultZoom) < 0.0001)
    }

    @Test("The percentage label reflects the current scale")
    func percentLabel() {
        var zoom = EditorZoom()
        #expect(zoom.percentLabel == "100%")
        zoom.scale = 1.5
        #expect(zoom.percentLabel == "150%")
    }

    @Test("Reset is reported as available only when zoomed")
    func canResetOnlyWhenZoomed() {
        var zoom = EditorZoom()
        #expect(zoom.canReset == false)
        zoom.zoomIn()
        #expect(zoom.canReset)
    }
}
