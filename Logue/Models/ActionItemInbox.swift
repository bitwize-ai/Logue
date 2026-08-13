import Foundation

// MARK: - ActionItemInboxMode

/// Which slice of the extracted action items is shown.
///
/// Deliberately not the due-date vocabulary `TaskFilter` uses. An inbox is a queue you
/// empty, and slicing a queue by due date is the job of the list you empty it into.
enum ActionItemInboxMode: String, CaseIterable, Sendable {
    /// Extracted, and the user has not yet decided what it is.
    case inbox
    /// Explicitly rejected. Kept visible so a wrong call is recoverable.
    case dismissed
    case all

    var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .dismissed: "Dismissed"
        case .all: "All"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .dismissed: "xmark.circle"
        case .all: "tray.full"
        }
    }
}

// MARK: - ActionItemInbox

/// Whether an extracted action item is still awaiting a decision.
///
/// Pure and view-free for the same reason `TaskFilter` is: "still undecided" is the whole
/// behaviour of this screen, and a rule that can only be exercised by clicking is a rule
/// that silently rots.
enum ActionItemInbox {
    /// `isPromoted` is passed in rather than looked up, so this stays free of `TaskStore`
    /// and the rule can be tested without a store.
    static func matches(
        _ item: ActionItem, mode: ActionItemInboxMode, isPromoted: Bool
    ) -> Bool {
        switch mode {
        case .all:
            true
        case .dismissed:
            item.isDismissed
        case .inbox:
            !item.isDismissed && !item.isCompleted && !isPromoted
        }
    }

    static func counts(
        _ items: [ActionItem], isPromoted: (ActionItem) -> Bool
    ) -> [ActionItemInboxMode: Int] {
        var result: [ActionItemInboxMode: Int] = [:]
        for mode in ActionItemInboxMode.allCases {
            result[mode] = items.filter {
                matches($0, mode: mode, isPromoted: isPromoted($0))
            }.count
        }
        return result
    }
}
