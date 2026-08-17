import Foundation
import Testing

@testable import Logue

/// The three ways the task inspector's text commit has destroyed a user's edit, as tests.
///
/// Every one of them shipped because the rule lived inside a SwiftUI view and nothing could
/// reach it. Each case below fails against one of the three previous shapes of that rule.
@Suite("TaskTextCommit")
struct TaskTextCommitTests {
    private func task(title: String = "Old", notes: String = "") -> TaskItem {
        var task = TaskItem(id: UUID())
        task.title = title
        task.notes = notes
        return task
    }

    // MARK: - Nothing typed

    @Test("Untouched fields produce no commit")
    func noEditProducesNothing() {
        let loaded = task(title: "Water the plants", notes: "before winter")
        #expect(TaskTextCommit.make(
            loadedFrom: loaded, titleDraft: "Water the plants", notesDraft: "before winter"
        ) == nil)
    }

    @Test("A title differing only by surrounding whitespace is not an edit")
    func whitespaceOnlyIsNotAnEdit() {
        // Sanitising happens before the comparison, so re-focusing a field cannot look like a
        // change and stamp updatedAt — which reorders any list sorted by recency.
        let loaded = task(title: "Water the plants")
        #expect(TaskTextCommit.make(
            loadedFrom: loaded, titleDraft: "  Water the plants  ", notesDraft: ""
        ) == nil)
    }

    // MARK: - Only what was typed

    @Test("Editing the notes commits the notes and not the title")
    func notesEditDoesNotCarryTheTitle() {
        // Defect 3: one guard covered both fields and then sent both. Rename the row in the
        // list, type a note in the inspector, click away — and the rename was written back to
        // the old title, in markdown mode trashing the renamed file with it.
        let loaded = task(title: "Old", notes: "")
        let commit = TaskTextCommit.make(loadedFrom: loaded, titleDraft: "Old", notesDraft: "a note")

        #expect(commit?.notes == "a note")
        #expect(commit?.title == nil)
    }

    @Test("Editing the title commits the title and not the notes")
    func titleEditDoesNotCarryTheNotes() {
        let loaded = task(title: "Old", notes: "kept")
        let commit = TaskTextCommit.make(loadedFrom: loaded, titleDraft: "New", notesDraft: "kept")

        #expect(commit?.title == "New")
        #expect(commit?.notes == nil)
    }

    @Test("Editing both commits both")
    func bothEditsCommit() {
        let loaded = task(title: "Old", notes: "")
        let commit = TaskTextCommit.make(loadedFrom: loaded, titleDraft: "New", notesDraft: "a note")

        #expect(commit?.title == "New")
        #expect(commit?.notes == "a note")
    }

    // MARK: - Applying

    @Test("A commit leaves every field it does not carry alone")
    func applyingTouchesOnlyWhatChanged() {
        // Defect 2: committing text rebuilt the whole record from a snapshot taken at
        // selection, putting back a due date, a priority, a tag, or a completion tick set
        // since. Only the named fields move now.
        var live = task(title: "Old", notes: "")
        live.priority = .high
        live.dueDate = Date(timeIntervalSince1970: 1_000_000)
        live.tags = ["home"]
        live.status = .done
        live.completedCount = 3

        let loaded = task(title: "Old", notes: "")
        let commit = TaskTextCommit(taskID: live.id, title: nil, notes: "a note")
        _ = loaded
        let applied = commit.applied(to: live)

        #expect(applied?.notes == "a note")
        #expect(applied?.title == "Old")
        #expect(applied?.priority == .high)
        #expect(applied?.dueDate == Date(timeIntervalSince1970: 1_000_000))
        #expect(applied?.tags == ["home"])
        #expect(applied?.status == .done)
        #expect(applied?.completedCount == 3)
    }

    @Test("A commit refuses a task it was not made for")
    func applyingRefusesTheWrongTask() {
        // Defect 1: the selection moved before the commit landed, so the outgoing row's title
        // was written onto the newly-selected one — in markdown mode renaming its file and
        // trashing the original. Two clicks, no typing required.
        let outgoing = task(title: "Old")
        let incoming = task(title: "Something else")
        let commit = TaskTextCommit(taskID: outgoing.id, title: "New", notes: nil)

        #expect(commit.applied(to: incoming) == nil)
        #expect(commit.applied(to: outgoing)?.title == "New")
    }

    @Test("The commit carries the task it was loaded from, not the one on screen")
    func commitCarriesTheLoadedTask() {
        let loaded = task(title: "Old")
        let commit = TaskTextCommit.make(loadedFrom: loaded, titleDraft: "New", notesDraft: "")
        #expect(commit?.taskID == loaded.id)
    }
}
