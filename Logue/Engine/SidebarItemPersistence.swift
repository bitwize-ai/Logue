import Foundation

/// Which surface a relaunch restores, as a pure mapping either way.
///
/// Lifted out of `MainWindowView` so the migration can be tested without touching
/// `UserDefaults`. Home was two items — `overview` and `agentChat` — before they merged,
/// and both spellings are already on disk. An unmapped string would send an upgrading
/// user somewhere they never left, so both are read and only the new one is written.
enum SidebarItemPersistence {
    static func item(forStored raw: String) -> SidebarItem? {
        switch raw {
        // Retired spellings. `overview` was the dashboard and `agentChat` was the chat;
        // they are one surface now, and both must land on it.
        case "home", "overview", "agentChat": .home
        case "pinned": .pinned
        case "recent": .recent
        case "allDocuments": .allDocuments
        case "allMeetings": .allMeetings
        case "actionItems": .actionItems
        case "templates": .templates
        case "trash": .trash
        default: nil
        }
    }

    static func stored(for item: SidebarItem?) -> String? {
        switch item {
        case .home: "home"
        case .pinned: "pinned"
        case .recent: "recent"
        case .allDocuments: "allDocuments"
        case .allMeetings: "allMeetings"
        case .actionItems: "actionItems"
        case .templates: "templates"
        case .trash: "trash"
        // Per-item selections aren't persisted — restored from the store's own
        // `selectedDocumentID` / `selectedMeetingID` instead.
        case .space, .document, .meeting, .none: nil
        }
    }
}
