import Foundation

// MARK: - LibraryPanel

/// A panel that lives inside a library surface rather than on the sidebar.
///
/// Named separately from the per-surface tool enums because this is the thing that travels
/// through persistence and the command palette — "open All Meetings *and* its action items"
/// is one intent, and splitting it across two values is how the two drift apart.
enum LibraryPanel: String, Sendable, Equatable, CaseIterable {
    case actionItems
    case templates

    /// The surface the panel belongs to.
    var host: SidebarItem {
        switch self {
        case .actionItems: .allMeetings
        case .templates: .allDocuments
        }
    }

    var title: String {
        switch self {
        case .actionItems: "Action Items"
        case .templates: "Templates"
        }
    }

    var symbolName: String {
        switch self {
        case .actionItems: "checklist"
        case .templates: "doc.on.doc"
        }
    }
}

// MARK: - SidebarSelectionMigration

/// What a persisted sidebar value means today.
///
/// Action Items and Templates used to be sidebar destinations and are now panels inside
/// All Meetings and All Documents. Anyone whose app last sat on one of them has that string
/// on disk, so it has to resolve to somewhere real — a launch into an unrecognised value is
/// a launch into whatever the fallback happens to be, which is not where they were.
///
/// Pure, so the mapping is tested directly rather than through a window.
enum SidebarSelectionMigration {
    struct Restored: Equatable {
        let item: SidebarItem
        /// The panel to open on arrival, for values that used to be their own surface.
        let panel: LibraryPanel?
    }

    static func restored(from raw: String) -> Restored? {
        // The two that moved. Kept as string literals rather than reading `LibraryPanel`'s
        // raw values, because these are historical on-disk values: renaming the enum case
        // must not silently change what an old install restores to.
        switch raw {
        case "actionItems": return Restored(item: .allMeetings, panel: .actionItems)
        case "templates": return Restored(item: .allDocuments, panel: .templates)
        default: break
        }

        guard let item = stableItem(from: raw) else { return nil }
        return Restored(item: item, panel: nil)
    }

    /// The value to write for a surface, or `nil` for selections that are not persisted.
    ///
    /// Per-document and per-meeting selections are deliberately not stored — those are
    /// restored from the stores' own `selectedDocumentID` / `selectedMeetingID`, and landing
    /// on a deleted item is worse than landing in chat.
    static func persistedValue(for item: SidebarItem) -> String? {
        switch item {
        case .agentChat: "agentChat"
        case .overview: "overview"
        case .pinned: "pinned"
        case .recent: "recent"
        case .allDocuments: "allDocuments"
        case .allMeetings: "allMeetings"
        case .tasks: "tasks"
        case .trash: "trash"
        case .space, .document, .meeting: nil
        }
    }

    private static func stableItem(from raw: String) -> SidebarItem? {
        switch raw {
        case "agentChat": .agentChat
        case "overview": .overview
        case "pinned": .pinned
        case "recent": .recent
        case "allDocuments": .allDocuments
        case "allMeetings": .allMeetings
        case "tasks": .tasks
        case "trash": .trash
        default: nil
        }
    }
}
