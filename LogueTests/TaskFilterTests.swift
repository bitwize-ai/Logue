import Foundation
@testable import Logue
import Testing

@Suite("TaskFilter")
struct TaskFilterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: iso) ?? .distantPast
    }

    private var now: Date { date("2026-08-12") }

    private var sample: [TaskItem] {
        [
            TaskItem(title: "Overdue", dueDate: date("2026-08-01"), tags: ["work"]),
            TaskItem(title: "Today", dueDate: date("2026-08-12")),
            TaskItem(title: "Upcoming", priority: .high, dueDate: date("2026-08-20"), tags: ["work"]),
            TaskItem(title: "Undated", priority: .low),
            TaskItem(title: "Finished", status: .done, dueDate: date("2026-08-05")),
        ]
    }

    private func titles(_ mode: TaskFilterMode, tag: String? = nil) -> [String] {
        TaskFilter.apply(sample, mode: mode, tag: tag, now: now, calendar: calendar).map(\.title)
    }

    // MARK: - Modes

    @Test("All shows every open task and hides completed ones")
    func allExcludesCompleted() {
        #expect(titles(.all).sorted() == ["Overdue", "Today", "Undated", "Upcoming"])
    }

    @Test("Today shows only what is due today")
    func todayFilter() {
        #expect(titles(.today) == ["Today"])
    }

    @Test("Overdue shows only what is past its date and still open")
    func overdueFilter() {
        #expect(titles(.overdue) == ["Overdue"])
    }

    @Test("A completed task is never overdue")
    func completedIsNotOverdue() {
        #expect(titles(.overdue).contains("Finished") == false)
    }

    @Test("A task due today is not overdue")
    func todayIsNotOverdue() {
        #expect(titles(.overdue).contains("Today") == false)
    }

    @Test("Upcoming shows future dates only")
    func upcomingFilter() {
        #expect(titles(.upcoming) == ["Upcoming"])
    }

    @Test("No-due-date shows only undated open tasks")
    func undatedFilter() {
        #expect(titles(.noDueDate) == ["Undated"])
    }

    @Test("Completed shows only finished tasks")
    func completedFilter() {
        #expect(titles(.completed) == ["Finished"])
    }

    // MARK: - Tags

    @Test("A tag narrows any mode")
    func tagNarrows() {
        #expect(titles(.all, tag: "work").sorted() == ["Overdue", "Upcoming"])
    }

    @Test("Tag matching ignores case")
    func tagCaseInsensitive() {
        #expect(titles(.all, tag: "WORK").isEmpty == false)
    }

    @Test("An empty tag does not narrow anything")
    func emptyTagIsNoOp() {
        #expect(titles(.all, tag: "").count == titles(.all).count)
    }

    @Test("An unknown tag matches nothing rather than everything")
    func unknownTagMatchesNothing() {
        #expect(titles(.all, tag: "nonexistent").isEmpty)
    }

    // MARK: - Sorting

    @Test("Sorting by due date puts undated tasks last, not first")
    func dueDateSortPutsUndatedLast() {
        // Treating a missing date as the distant past would put every undated task above
        // everything urgent, which is the opposite of useful.
        #expect(TaskFilter.sort(sample, by: .dueDateAsc).map(\.title).last == "Undated")
    }

    @Test("Sorting by due date is ascending")
    func dueDateSortAscending() {
        let dated = TaskFilter.sort(sample, by: .dueDateAsc)
            .compactMap { $0.dueDate == nil ? nil : $0.title }
        // Overdue is 08-01, Finished 08-05, Today 08-12, Upcoming 08-20.
        #expect(dated == ["Overdue", "Finished", "Today", "Upcoming"])
    }

    @Test("Sorting by priority puts high first")
    func prioritySort() {
        let sorted = TaskFilter.sort(sample, by: .priorityDesc).map(\.title)
        #expect(sorted.first == "Upcoming")
        #expect(sorted.last == "Undated")
    }

    @Test("Sorting by title is case-insensitive")
    func titleSort() {
        let tasks = [TaskItem(title: "banana"), TaskItem(title: "Apple")]
        #expect(TaskFilter.sort(tasks, by: .title).map(\.title) == ["Apple", "banana"])
    }

    @Test("Sorting an empty list is not an error")
    func sortEmpty() {
        for order in TaskSortOrder.allCases {
            #expect(TaskFilter.sort([], by: order).isEmpty)
        }
    }

    @Test("Sorting is stable enough to be deterministic for equal keys")
    func sortDeterministic() {
        let tasks = [TaskItem(title: "b"), TaskItem(title: "a"), TaskItem(title: "c")]
        #expect(
            TaskFilter.sort(tasks, by: .dueDateAsc).map(\.title)
                == TaskFilter.sort(tasks, by: .dueDateAsc).map(\.title)
        )
    }

    // MARK: - Search

    private func searched(_ text: String) -> [String] {
        TaskFilter.apply(
            sample, mode: .all, tag: nil, searchText: text, now: now, calendar: calendar
        )
        .map(\.title)
    }

    @Test("Empty search leaves the list alone")
    func emptySearchIsNoOp() {
        #expect(searched("") == titles(.all))
    }

    @Test("Search matches the title case-insensitively")
    func searchMatchesTitle() {
        #expect(searched("upcom") == ["Upcoming"])
        #expect(searched("UPCOM") == ["Upcoming"])
    }

    @Test("Search matches a tag")
    func searchMatchesTag() {
        #expect(searched("work").sorted() == ["Overdue", "Upcoming"])
    }

    @Test("Search matches the notes body")
    func searchMatchesNotes() {
        let tasks = [TaskItem(title: "Opaque", notes: "Assigned to: Priya")]
        let found = TaskFilter.apply(
            tasks, mode: .all, tag: nil, searchText: "priya", now: now, calendar: calendar
        )
        #expect(found.map(\.title) == ["Opaque"])
    }

    @Test("A search that matches nothing returns nothing")
    func searchWithNoMatches() {
        #expect(searched("zzzz").isEmpty)
    }
}
