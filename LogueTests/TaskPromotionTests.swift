import Foundation
@testable import Logue
import Testing

@Suite("TaskPromotion")
struct TaskPromotionTests {
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: iso) ?? .distantPast
    }

    private let meetingID = UUID()

    private func actionItem(
        title: String = "Send the revised deck to Priya",
        assignee: String? = nil,
        dueDescription: String? = nil,
        isCompleted: Bool = false,
        dueDate: Date? = nil
    ) -> ActionItem {
        ActionItem(
            title: title,
            assignee: assignee,
            dueDescription: dueDescription,
            isCompleted: isCompleted,
            dueDate: dueDate
        )
    }

    // MARK: - Conversion

    @Test("The title carries across")
    func titleCarries() {
        let task = TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now)
        #expect(task.title == "Send the revised deck to Priya")
    }

    @Test("The task keeps a link back to the meeting it was decided in")
    func meetingLinkKept() {
        let task = TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now)
        #expect(task.sourceMeetingID == meetingID)
    }

    @Test("The task reuses the action item's identifier, so promotion can be recognised later")
    func identifierReused() {
        let item = actionItem()
        #expect(TaskItem(actionItem: item, meetingID: meetingID, now: .now).id == item.id)
    }

    @Test("A due date carries across")
    func dueDateCarries() {
        let task = TaskItem(
            actionItem: actionItem(dueDate: date("2026-08-14")), meetingID: meetingID, now: .now
        )
        #expect(task.dueDate == date("2026-08-14"))
    }

    @Test("A completed action item becomes a completed task")
    func completionCarries() {
        let task = TaskItem(
            actionItem: actionItem(isCompleted: true), meetingID: meetingID, now: .now
        )
        #expect(task.status == .done)
    }

    @Test("An assignee is kept in the notes rather than dropped")
    func assigneeKeptInNotes() {
        let task = TaskItem(
            actionItem: actionItem(assignee: "Priya"), meetingID: meetingID, now: .now
        )
        #expect(task.notes.contains("Priya"))
    }

    @Test("A vague due description is kept in the notes rather than dropped")
    func dueDescriptionKeptInNotes() {
        let task = TaskItem(
            actionItem: actionItem(dueDescription: "before the board meeting"),
            meetingID: meetingID,
            now: .now
        )
        #expect(task.notes.contains("before the board meeting"))
    }

    @Test("A vague due description is dropped once a real date resolved it")
    func dueDescriptionOmittedWhenDated() {
        let task = TaskItem(
            actionItem: actionItem(
                dueDescription: "before the board meeting", dueDate: date("2026-08-14")
            ),
            meetingID: meetingID,
            now: .now
        )
        #expect(task.notes.contains("before the board meeting") == false)
    }

    @Test("An action item with neither extra produces empty notes, not a stub heading")
    func notesEmptyWhenNothingToKeep() {
        #expect(TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now).notes.isEmpty)
    }

    @Test("A promoted task starts at medium priority — the model did not rank it")
    func priorityIsNeutral() {
        #expect(
            TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now).priority == .medium
        )
    }

    @Test("A promoted task does not repeat")
    func promotedTaskDoesNotRepeat() {
        #expect(TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now).recurrence == nil)
    }

    // MARK: - Idempotency

    @Test("Re-promoting updates the existing task rather than duplicating it")
    func mergeKeepsIdentity() {
        let item = actionItem()
        let first = TaskItem(actionItem: item, meetingID: meetingID, now: .now)
        #expect(TaskStore.merging(item, into: first, now: .now).id == first.id)
    }

    @Test("A merge does not clobber edits the user made to the task")
    func mergePreservesUserEdits() {
        let item = actionItem()
        var existing = TaskItem(actionItem: item, meetingID: meetingID, now: .now)
        existing.priority = .high
        existing.tags = ["launch"]
        existing.notes = "My own note"

        let merged = TaskStore.merging(item, into: existing, now: .now)
        #expect(merged.priority == .high)
        #expect(merged.tags == ["launch"])
        #expect(merged.notes == "My own note")
    }

    @Test("A merge does not resurrect a task the user completed")
    func mergeDoesNotReopenCompleted() {
        let item = actionItem()
        var existing = TaskItem(actionItem: item, meetingID: meetingID, now: .now)
        existing.status = .done
        #expect(TaskStore.merging(item, into: existing, now: .now).status == .done)
    }

    @Test("A merge takes a due date the meeting has gained and the task lacks")
    func mergeFillsMissingDueDate() {
        var existing = TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now)
        existing.dueDate = nil

        let merged = TaskStore.merging(
            actionItem(dueDate: date("2026-08-14")), into: existing, now: .now
        )
        #expect(merged.dueDate == date("2026-08-14"))
    }

    @Test("A merge does not overwrite a due date the user chose")
    func mergeKeepsUserDueDate() {
        var existing = TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now)
        existing.dueDate = date("2026-09-01")

        let merged = TaskStore.merging(
            actionItem(dueDate: date("2026-08-14")), into: existing, now: .now
        )
        #expect(merged.dueDate == date("2026-09-01"))
    }

    @Test("A merge keeps the original meeting link")
    func mergeKeepsMeetingLink() {
        let existing = TaskItem(actionItem: actionItem(), meetingID: meetingID, now: .now)
        #expect(TaskStore.merging(actionItem(), into: existing, now: .now).sourceMeetingID == meetingID)
    }

    // MARK: - Hostile input

    @Test("Emoji in an action item title survive promotion")
    func multiByteSurvives() {
        let task = TaskItem(
            actionItem: actionItem(title: "送出簡報 📊"), meetingID: meetingID, now: .now
        )
        #expect(task.title == "送出簡報 📊")
    }

    @Test("An over-long action item title is truncated to the task limit")
    func longTitleTruncated() {
        let task = TaskItem(
            actionItem: actionItem(title: String(repeating: "a", count: 500)),
            meetingID: meetingID,
            now: .now
        )
        #expect(task.title.count <= TaskItem.maxTitleLength)
    }

    @Test("A newline in an action item title does not survive into a task")
    func newlineStripped() {
        let task = TaskItem(
            actionItem: actionItem(title: "Send the deck\nthen rest"),
            meetingID: meetingID,
            now: .now
        )
        #expect(task.title.contains("\n") == false)
    }

    @Test("A blank action item title falls back rather than producing an unnamed task")
    func blankTitleFallsBack() {
        let task = TaskItem(actionItem: actionItem(title: "   "), meetingID: meetingID, now: .now)
        #expect(task.title.isEmpty == false)
    }
}
