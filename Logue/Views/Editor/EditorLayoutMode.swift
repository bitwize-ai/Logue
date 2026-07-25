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
}
