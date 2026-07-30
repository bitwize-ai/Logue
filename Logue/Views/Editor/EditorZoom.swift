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

extension EditorZoom {
    /// Reads the persisted scale, applies `mutate`, and writes the clamped result back.
    ///
    /// Two places drive zoom — the View menu items and the main window's own key handling for
    /// the `⌘=` alias — and the clamping has to stay in one place, so they meet at the stored
    /// value rather than at a binding one of them owns. Writing through `UserDefaults` is what
    /// makes that work: the `@AppStorage` properties reading this key update from it.
    static func mutatePersisted(_ mutate: (inout EditorZoom) -> Void) {
        let key = AppConstants.UserDefaultsKeys.editorZoomScale
        var zoom = EditorZoom()
        if let stored = UserDefaults.standard.object(forKey: key) as? Double {
            zoom.scale = CGFloat(stored)
        }
        mutate(&zoom)
        UserDefaults.standard.set(Double(zoom.scale), forKey: key)
    }
}
