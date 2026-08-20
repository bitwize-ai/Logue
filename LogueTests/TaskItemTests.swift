import Foundation
@testable import Logue
import Testing

@Suite("TaskItem")
struct TaskItemTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed zone, because month arithmetic across a DST boundary is exactly
        // where a hidden `Calendar.current` produces a test that passes in one timezone.
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

    // MARK: - Priority

    @Test("Priority orders low below high")
    func priorityOrders() {
        #expect(TaskPriority.low < TaskPriority.medium)
        #expect(TaskPriority.medium < TaskPriority.high)
    }

    // MARK: - Recurrence

    @Test("An interval below one is clamped, so a task cannot reopen on the same day forever")
    func intervalClampedLow() {
        #expect(TaskRecurrence(unit: .day, interval: 0).interval == 1)
        #expect(TaskRecurrence(unit: .day, interval: -5).interval == 1)
    }

    @Test("An absurd interval is clamped to a year")
    func intervalClampedHigh() {
        #expect(TaskRecurrence(unit: .day, interval: 10000).interval == TaskRecurrence.maxInterval)
    }

    @Test("A weekly recurrence advances seven days")
    func weeklyAdvances() {
        let next = TaskRecurrence(unit: .week, interval: 1)
            .nextDueDate(after: date("2026-08-12"), calendar: utc)
        #expect(next == date("2026-08-19"))
    }

    @Test("A monthly recurrence advances a calendar month, not thirty days")
    func monthlyAdvances() {
        let next = TaskRecurrence(unit: .month, interval: 1)
            .nextDueDate(after: date("2026-01-31"), calendar: utc)
        #expect(next == date("2026-02-28"))
    }

    @Test("Recurrence round-trips through its storage string")
    func recurrenceRoundTrips() throws {
        for recurrence in [
            TaskRecurrence(unit: .day, interval: 3),
            TaskRecurrence(unit: .week, interval: 2),
            TaskRecurrence(unit: .month, interval: 6),
        ] {
            let parsed = try #require(TaskRecurrence.parse(recurrence.storageString))
            #expect(parsed == recurrence)
        }
    }

    @Test("The words a person types by hand are understood")
    func recurrenceWords() {
        #expect(TaskRecurrence.parse("daily") == TaskRecurrence(unit: .day, interval: 1))
        #expect(TaskRecurrence.parse("weekly") == TaskRecurrence(unit: .week, interval: 1))
        #expect(TaskRecurrence.parse("monthly") == TaskRecurrence(unit: .month, interval: 1))
    }

    @Test("An unparseable recurrence is refused rather than guessed")
    func recurrenceRefused() {
        #expect(TaskRecurrence.parse("every so often") == nil)
        #expect(TaskRecurrence.parse("") == nil)
        #expect(TaskRecurrence.parse("5") == nil)
        #expect(TaskRecurrence.parse("x9") == nil)
    }

    // MARK: - Codable

    @Test("A task round-trips through Codable")
    func taskRoundTrips() throws {
        let task = TaskItem(
            title: "Send the deck 📊",
            status: .todo,
            priority: .high,
            dueDate: date("2026-08-14"),
            tags: ["launch"],
            recurrence: TaskRecurrence(unit: .week, interval: 1),
            completedCount: 2,
            sourceMeetingID: UUID(),
            notes: "Split the pricing slide"
        )
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        #expect(decoded == task)
    }

    @Test("A payload missing every optional key still decodes")
    func minimalPayloadDecodes() throws {
        let json = Data(#"{"id":"\#(UUID().uuidString)","title":"Bare"}"#.utf8)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: json)
        #expect(decoded.title == "Bare")
        #expect(decoded.status == .todo)
        #expect(decoded.priority == .medium)
        #expect(decoded.tags.isEmpty)
        #expect(decoded.completedCount == 0)
    }
}
