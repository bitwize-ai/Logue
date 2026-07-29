import Foundation

/// Which panes the main window shows. Driven by Cmd+1 / Cmd+2 / Cmd+3.
enum EditorLayoutMode: String, CaseIterable, Codable, Sendable {
    case editorOnly
    case editorAndList
    case allPanels

    init?(shortcutNumber: Int) {
        switch shortcutNumber {
        case 1: self = .editorOnly
        case 2: self = .editorAndList
        case 3: self = .allPanels
        default: return nil
        }
    }

    var showsList: Bool {
        self != .editorOnly
    }

    var showsInspector: Bool {
        self == .allPanels
    }

    var label: String {
        switch self {
        case .editorOnly: "Editor Only"
        case .editorAndList: "Editor and List"
        case .allPanels: "All Panels"
        }
    }

    /// The mode a split-view visibility report should store, or `nil` to leave the mode alone.
    ///
    /// Only a collapse is inferred, and that asymmetry is the whole point. SwiftUI echoes the
    /// new visibility back through its `columnVisibility` binding immediately after a menu item
    /// sets a mode, and the echo arrives while the binding still reads the previous mode —
    /// `@AppStorage` caches, so a setter cannot see the write it is echoing. A rule that tried
    /// to name the mode for a *re-appearing* list therefore read the old mode's
    /// `showsInspector`, which is `false` in editor-only, and turned every ⌘3 pressed from
    /// editor-only into editor-and-list. Nothing needs that direction inferred: every path that
    /// shows the list again already names the mode it wants.
    static func modeAfterVisibilityReport(listIsVisible: Bool) -> EditorLayoutMode? {
        listIsVisible ? nil : .editorOnly
    }

    /// The persisted layout, read straight from `UserDefaults`.
    ///
    /// Exists so a `@State` property can be initialised from the stored mode — a property
    /// initialiser cannot read another wrapper's value. Views that need to *react* to the
    /// mode changing observe the `@AppStorage` key instead.
    static var stored: EditorLayoutMode {
        guard let raw = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaultsKeys.editorLayoutMode
        )
        else { return .allPanels }
        return EditorLayoutMode(rawValue: raw) ?? .allPanels
    }
}
