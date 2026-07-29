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
