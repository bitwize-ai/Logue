import Foundation

/// Editor text zoom, clamped to the bounds in `AppConstants.Editor`.
///
/// A value type so a view can hold it in `@State` and it stays trivially testable.
/// The scale multiplies font sizes rather than transforming the view, so text stays
/// crisp and line wrapping recalculates at the new size.
struct EditorZoom: Equatable {
    private var storedScale: CGFloat = AppConstants.Editor.defaultZoom

    /// Current zoom multiplier. Assignments are clamped to the allowed range.
    var scale: CGFloat {
        get { storedScale }
        set { storedScale = Self.clamp(newValue) }
    }

    var canReset: Bool {
        abs(storedScale - AppConstants.Editor.defaultZoom) > 0.0001
    }

    var percentLabel: String {
        "\(Int((storedScale * 100).rounded()))%"
    }

    mutating func zoomIn() {
        scale = storedScale + AppConstants.Editor.zoomStep
    }

    mutating func zoomOut() {
        scale = storedScale - AppConstants.Editor.zoomStep
    }

    mutating func reset() {
        scale = AppConstants.Editor.defaultZoom
    }

    /// Applies the zoom to a base font size.
    func scaled(_ size: CGFloat) -> CGFloat {
        size * storedScale
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, AppConstants.Editor.minZoom), AppConstants.Editor.maxZoom)
    }
}
