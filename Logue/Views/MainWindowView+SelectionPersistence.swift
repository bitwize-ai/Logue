import SwiftUI

// MARK: - Sidebar selection persistence

/// Remembering which sidebar surface the window was last on.
///
/// Split out of `MainWindowView` to keep that type within the project's body-length limit.
/// These are `static` and touch nothing on the view, so they carry across cleanly.
extension MainWindowView {
    /// UserDefaults key for the last-stable sidebar surface. Document and meeting selections
    /// are restored separately via the per-store `selectedDocumentID` / `selectedMeetingID`,
    /// so only coarse surfaces are persisted here.
    private static var lastSidebarKey: String { "MainWindow.lastSidebarSelection" }

    /// Loads the last-stable sidebar surface, or `nil` on a fresh install.
    /// `MainWindowView` falls back to `.agentChat` when this returns `nil`.
    static func loadLastSidebarSelection() -> SidebarItem? {
        guard let raw = UserDefaults.standard.string(forKey: lastSidebarKey) else { return nil }
        switch raw {
        case "agentChat": return .agentChat
        case "overview": return .overview
        case "pinned": return .pinned
        case "recent": return .recent
        case "allDocuments": return .allDocuments
        case "allMeetings": return .allMeetings
        case "actionItems": return .actionItems
        case "tasks": return .tasks
        case "templates": return .templates
        case "trash": return .trash
        default: return nil
        }
    }

    /// Persists only "stable" sidebar surfaces. Per-document and per-meeting selections are
    /// intentionally not persisted — those are restored via the store's `selectedDocumentID`
    /// / `selectedMeetingID`, and a deleted-document landing screen is worse than landing in
    /// chat.
    static func persistSidebarSelection(_ item: SidebarItem?) {
        let raw: String? = switch item {
        case .agentChat: "agentChat"
        case .overview: "overview"
        case .pinned: "pinned"
        case .recent: "recent"
        case .allDocuments: "allDocuments"
        case .allMeetings: "allMeetings"
        case .actionItems: "actionItems"
        case .tasks: "tasks"
        case .templates: "templates"
        case .trash: "trash"
        // Per-item selections aren't persisted — see doc comment.
        case .space, .document, .meeting, .none: nil
        }
        if let raw {
            UserDefaults.standard.setValue(raw, forKey: lastSidebarKey)
        }
    }
}
