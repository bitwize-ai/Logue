import Foundation

/// Which panes the main window shows. Driven by Cmd+1 / Cmd+2 / Cmd+3.
/// The four cases are the four combinations of (list, inspector), not a progression.
/// `editorAndInspector` exists because closing the navigation sidebar must not take the
/// inspector with it: without a state meaning "no list, inspector still up", collapsing
/// from `allPanels` had nowhere to land but `editorOnly`, and the right sidebar vanished
/// along with the left.
enum EditorLayoutMode: String, CaseIterable, Codable, Sendable {
    case editorOnly
    case editorAndList
    case allPanels
    case editorAndInspector

    init?(shortcutNumber: Int) {
        switch shortcutNumber {
        case 1: self = .editorOnly
        case 2: self = .editorAndList
        case 3: self = .allPanels
        case 4: self = .editorAndInspector
        default: return nil
        }
    }

    var showsList: Bool {
        self == .editorAndList || self == .allPanels
    }

    var showsInspector: Bool {
        self == .allPanels || self == .editorAndInspector
    }

    var label: String {
        switch self {
        case .editorOnly: "Editor Only"
        case .editorAndList: "Editor and List"
        case .allPanels: "All Panels"
        case .editorAndInspector: "Editor and Inspector"
        }
    }

    /// The same panes with the list hidden, and with the list shown. Together they make
    /// hiding and showing the navigation sidebar exact inverses, which is what stops a
    /// collapse from quietly costing the inspector too.
    var withoutList: EditorLayoutMode {
        showsInspector ? .editorAndInspector : .editorOnly
    }

    var withList: EditorLayoutMode {
        showsInspector ? .allPanels : .editorAndList
    }

    /// The mode a split-view visibility report should store, or `nil` to leave the mode alone.
    ///
    /// Both directions are honoured, and what makes that safe is `current`. SwiftUI echoes the
    /// new visibility back through its `columnVisibility` binding immediately after a menu item
    /// sets a mode, so a report has to be told apart from an echo of our own write. A report
    /// that *agrees* with the stored mode is an echo and changes nothing; only one that
    /// disagrees is a user acting on the split view.
    ///
    /// `current` must be read fresh from `UserDefaults` — `EditorLayoutMode.stored` — and not
    /// from the caller's `@AppStorage` property. The wrapper caches, so a setter cannot see the
    /// write it is echoing, and a stale `current` makes every echo look like a disagreement.
    /// That stale read is the original bug here: it turned every ⌘3 pressed from editor-only
    /// into editor-and-list. The earlier fix was to ignore visible-list reports outright, which
    /// cost the window its sidebar toggle — the button reported the list as visible, the report
    /// was dropped, and nothing happened — and made a sidebar dragged shut unrecoverable except
    /// by ⌘1 / ⌘2 / ⌘3.
    ///
    /// Only the list is touched. The inspector is left exactly as it was, so closing the
    /// navigation sidebar no longer closes the tools sidebar with it — see `withoutList`.
    static func modeAfterVisibilityReport(
        listIsVisible: Bool,
        current: EditorLayoutMode
    ) -> EditorLayoutMode? {
        guard listIsVisible != current.showsList else { return nil }
        return listIsVisible ? current.withList : current.withoutList
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
