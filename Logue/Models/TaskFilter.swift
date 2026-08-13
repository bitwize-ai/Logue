import Foundation

// MARK: - TaskFilterMode

/// Which slice of the list is shown.
///
/// This is where the due-date vocabulary lives. The action item screen is a triage inbox
/// (`ActionItemInboxMode`) and deliberately does not repeat it — work the user has accepted
/// is sliced by date here, in one place.
enum TaskFilterMode: String, CaseIterable, Codable, Sendable {
    case all
    case today
    case overdue
    case upcoming
    case noDueDate
    case completed

    var displayName: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .overdue: "Overdue"
        case .upcoming: "Upcoming"
        case .noDueDate: "No Date"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .today: "calendar"
        case .overdue: "exclamationmark.triangle"
        case .upcoming: "calendar.badge.clock"
        case .noDueDate: "calendar.badge.exclamationmark"
        case .completed: "checkmark.circle"
        }
    }
}

// MARK: - TaskSortOrder

enum TaskSortOrder: String, CaseIterable, Codable, Sendable {
    case dueDateAsc
    case priorityDesc
    case createdNewest
    case title

    var displayName: String {
        switch self {
        case .dueDateAsc: "Due Date"
        case .priorityDesc: "Priority"
        case .createdNewest: "Recently Added"
        case .title: "Title"
        }
    }
}

// MARK: - TaskFilter

/// Pure filtering and sorting, so the list's behaviour is testable without a view.
///
/// `now` and `calendar` are parameters rather than `Date()` and `.current` for the same
/// reason they are in the parser: "overdue" has to mean the same thing twice.
enum TaskFilter {
    static func apply(
        _ tasks: [TaskItem],
        mode: TaskFilterMode,
        tag: String?,
        searchText: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let startOfToday = calendar.startOfDay(for: now)
        let matched = tasks.filter { matches($0, mode: mode, startOfToday: startOfToday, calendar: calendar) }

        guard let tag, !tag.isEmpty else { return applySearch(matched, searchText) }
        let tagged = matched.filter { task in
            task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        return applySearch(tagged, searchText)
    }

    /// Title, tags and notes — the three places a task's words live.
    private static func applySearch(_ tasks: [TaskItem], _ searchText: String) -> [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }
        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query)
                || task.notes.localizedCaseInsensitiveContains(query)
                || task.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private static func matches(
        _ task: TaskItem, mode: TaskFilterMode, startOfToday: Date, calendar: Calendar
    ) -> Bool {
        switch mode {
        case .all:
            return task.status == .todo
        case .completed:
            return task.status == .done
        case .noDueDate:
            return task.status == .todo && task.dueDate == nil
        case .today:
            guard task.status == .todo, let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: startOfToday)
        case .overdue:
            guard task.status == .todo, let due = task.dueDate else { return false }
            // Strictly before today: something due today is due, not late.
            return due < startOfToday && !calendar.isDate(due, inSameDayAs: startOfToday)
        case .upcoming:
            guard task.status == .todo, let due = task.dueDate else { return false }
            return due > startOfToday && !calendar.isDate(due, inSameDayAs: startOfToday)
        }
    }

    static func sort(_ tasks: [TaskItem], by order: TaskSortOrder) -> [TaskItem] {
        switch order {
        case .dueDateAsc:
            // Undated tasks sort last. Treating a missing date as `.distantPast` would put
            // every undated task above everything urgent, which is the opposite of useful.
            tasks.sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    left == right ? lhs.title < rhs.title : left < right
                case (nil, _?):
                    false
                case (_?, nil):
                    true
                case (nil, nil):
                    lhs.title < rhs.title
                }
            }
        case .priorityDesc:
            tasks.sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.title < rhs.title : lhs.priority > rhs.priority
            }
        case .createdNewest:
            tasks.sorted { $0.createdAt > $1.createdAt }
        case .title:
            tasks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}
