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
/// Four sidebar destinations have been retired, in two separate moves, and every one of them
/// is a string sitting on an existing install's disk:
///
/// - `actionItems` and `templates` became panels inside All Meetings and All Documents.
/// - `overview` and `agentChat` merged into a single `home` surface.
///
/// All four have to resolve to somewhere real. A launch on an unrecognised value is a launch
/// into whatever the fallback happens to be, which is not where the user left off.
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

        // The two that merged. `overview` was the dashboard and `agentChat` the chat; they
        // are one surface now, so both land on it rather than on the fallback.
        if raw == "overview" || raw == "agentChat" {
            return Restored(item: .home, panel: nil)
        }

        guard let item = stableItem(from: raw) else { return nil }
        return Restored(item: item, panel: nil)
    }

    /// The value to write for a surface, or `nil` for selections that are not persisted.
    ///
    /// Per-document and per-meeting selections are deliberately not stored — those are
    /// restored from the stores' own `selectedDocumentID` / `selectedMeetingID`, and landing
    /// on a deleted item is worse than landing on Home.
    static func persistedValue(for item: SidebarItem) -> String? {
        switch item {
        case .home: "home"
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
        case "home": .home
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
