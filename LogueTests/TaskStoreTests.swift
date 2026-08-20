import Foundation
@testable import Logue
import Testing

@Suite("TaskStore")
struct TaskStoreTests {
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

    private func day(_ value: Date?) -> String? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }

    private func complete(_ task: TaskItem, on today: String = "2026-08-12") -> TaskItem {
        TaskStore.completing(task, now: date(today), calendar: calendar)
    }

    // MARK: - Completing a one-off task

    @Test("Completing a plain task marks it done")
    func plainTaskCompletes() {
        #expect(complete(TaskItem(title: "Ship it")).status == .done)
    }

    @Test("Completing a done task reopens it")
    func completingTwiceReopens() {
        #expect(complete(TaskItem(title: "Ship it", status: .done)).status == .todo)
    }

    @Test("Completing stamps the update time")
    func completionStampsUpdate() {
        let original = TaskItem(title: "Ship it", updatedAt: date("2026-01-01"))
        #expect(complete(original).updatedAt > original.updatedAt)
    }

    @Test("Completing does not invent a due date for an undated one-off task")
    func plainTaskKeepsNoDueDate() {
        #expect(complete(TaskItem(title: "Ship it")).dueDate == nil)
    }

    // MARK: - Completing a repeating task

    @Test("A repeating task reopens rather than closing")
    func repeatingReopens() {
        let task = TaskItem(
            title: "Water the plants",
            dueDate: date("2026-08-10"),
            recurrence: TaskRecurrence(unit: .week, interval: 1)
        )
        #expect(complete(task).status == .todo)
    }

    @Test("A repeating task advances from its old due date, not from today")
    func advancesFromOldDueDate() {
        // Due Monday, completed three days late on Wednesday: the next one is the following
        // Monday, not the following Wednesday — otherwise it drifts later every cycle.
        let task = TaskItem(
            title: "Water the plants",
            dueDate: date("2026-08-10"),
            recurrence: TaskRecurrence(unit: .week, interval: 1)
        )
        #expect(day(complete(task, on: "2026-08-12").dueDate) == "2026-08-17")
    }

    @Test("A repeating task with no due date advances from today")
    func advancesFromTodayWhenUndated() {
        let task = TaskItem(
            title: "Water the plants",
            recurrence: TaskRecurrence(unit: .day, interval: 1)
        )
        #expect(day(complete(task, on: "2026-08-12").dueDate) == "2026-08-13")
    }

    @Test("Completing a repeating task counts the completion")
    func completionCounted() {
        let task = TaskItem(
            title: "Water the plants",
            dueDate: date("2026-08-10"),
            recurrence: TaskRecurrence(unit: .week, interval: 1),
            completedCount: 2
        )
        #expect(complete(task).completedCount == 3)
    }

    @Test("Reopening a repeating task does not create a second task")
    func repeatingKeepsIdentity() {
        let task = TaskItem(
            title: "Water the plants",
            dueDate: date("2026-08-10"),
            recurrence: TaskRecurrence(unit: .week, interval: 1)
        )
        #expect(complete(task).id == task.id)
    }

    @Test("An already-done repeating task reopens without advancing again")
    func doneRepeatingDoesNotDoubleAdvance() {
        // An accidental double-click must not push the task another week out.
        let task = TaskItem(
            title: "Water the plants",
            status: .done,
            dueDate: date("2026-08-17"),
            recurrence: TaskRecurrence(unit: .week, interval: 1),
            completedCount: 1
        )
        let reopened = complete(task)
        #expect(reopened.status == .todo)
        #expect(day(reopened.dueDate) == "2026-08-17")
        #expect(reopened.completedCount == 1)
    }

    @Test("A long-overdue repeating task still advances only one cycle")
    func overdueRepeatingAdvancesOneCycle() {
        let task = TaskItem(
            title: "Water the plants",
            dueDate: date("2026-01-05"),
            recurrence: TaskRecurrence(unit: .week, interval: 1)
        )
        #expect(day(complete(task, on: "2026-08-12").dueDate) == "2026-01-12")
    }

    // MARK: - Capture

    @Test("Capture creates one task per line")
    func captureSplits() {
        let created = TaskStore.captured(
            from: "call mom\nbuy milk", now: date("2026-08-12"), calendar: calendar
        )
        #expect(created.map(\.title) == ["call mom", "buy milk"])
    }

    @Test("Capture applies the parsed metadata")
    func captureParses() {
        let created = TaskStore.captured(
            from: "Send the deck tomorrow #launch !", now: date("2026-08-12"), calendar: calendar
        )
        let task = created.first
        #expect(task?.title == "Send the deck")
        #expect(task?.priority == .high)
        #expect(task?.tags == ["launch"])
        #expect(day(task?.dueDate) == "2026-08-13")
    }

    @Test("Capture of blank text creates nothing")
    func captureBlank() {
        #expect(TaskStore.captured(from: "   \n\n ", now: .now, calendar: calendar).isEmpty)
    }

    @Test("Each captured task gets its own identifier")
    func captureIdentifiersUnique() {
        let created = TaskStore.captured(from: "a\nb\nc", now: .now, calendar: calendar)
        #expect(Set(created.map(\.id)).count == 3)
    }

    @Test("Captured tasks are stamped with the supplied clock, not the wall clock")
    func captureStampsSuppliedClock() {
        let now = date("2026-08-12")
        let created = TaskStore.captured(from: "call mom", now: now, calendar: calendar)
        #expect(created.first?.createdAt == now)
    }
}
