import SwiftUI

// MARK: - Sort Options

enum ActionItemSortOrder: String, CaseIterable {
    case dueDateAsc = "Due Date (Soonest)"
    case dueDateDesc = "Due Date (Latest)"
    case createdNewest = "Recently Added"
    case createdOldest = "Oldest First"
    case meetingTitle = "Meeting Title"
    case status = "Status"
}

// MARK: - Dashboard Action Item (aggregated view model)

/// A single action item with its meeting context.
struct DashboardActionItem: Identifiable, Hashable {
    let actionItem: ActionItem
    let meetingID: UUID
    let meetingTitle: String

    var id: UUID {
        actionItem.id
    }

    static func == (lhs: DashboardActionItem, rhs: DashboardActionItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension DashboardActionItem {
    enum Urgency {
        case completed
        case overdue
        case dueToday
        case dueThisWeek
        case upcoming
        case noDate

        var color: Color {
            switch self {
            case .completed: AppThemeConstants.success
            case .overdue: AppThemeConstants.error
            case .dueToday: AppThemeConstants.warning
            case .dueThisWeek: AppThemeConstants.warning
            case .upcoming: AppThemeConstants.accent
            case .noDate: .secondary
            }
        }
    }

    var urgency: Urgency {
        if actionItem.isCompleted {
            return .completed
        }
        guard let due = actionItem.dueDate else { return .noDate }
        let now = Date()
        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        let startOfNextWeek = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 7, to: now) ?? now
        )
        if due < now {
            return .overdue
        }
        if due < startOfTomorrow {
            return .dueToday
        }
        if due < startOfNextWeek {
            return .dueThisWeek
        }
        return .upcoming
    }
}

// MARK: - Sorting

extension [DashboardActionItem] {
    func sorted(by order: ActionItemSortOrder) -> [DashboardActionItem] {
        switch order {
        case .dueDateAsc:
            sorted { lhs, rhs in
                (lhs.actionItem.dueDate ?? .distantFuture)
                    < (rhs.actionItem.dueDate ?? .distantFuture)
            }
        case .dueDateDesc:
            sorted { lhs, rhs in
                (lhs.actionItem.dueDate ?? .distantPast)
                    > (rhs.actionItem.dueDate ?? .distantPast)
            }
        case .createdNewest:
            sorted { $0.actionItem.createdAt > $1.actionItem.createdAt }
        case .createdOldest:
            sorted { $0.actionItem.createdAt < $1.actionItem.createdAt }
        case .meetingTitle:
            sorted {
                $0.meetingTitle.localizedCaseInsensitiveCompare($1.meetingTitle) == .orderedAscending
            }
        case .status:
            sorted { lhs, rhs in
                if lhs.actionItem.isCompleted != rhs.actionItem.isCompleted {
                    return !lhs.actionItem.isCompleted
                }
                return (lhs.actionItem.dueDate ?? .distantFuture)
                    < (rhs.actionItem.dueDate ?? .distantFuture)
            }
        }
    }
}
