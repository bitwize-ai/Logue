import Foundation
import Testing

@testable import Logue

/// The load direction of the task inspector's text fields.
///
/// `TaskTextCommit` covers what gets written; this covers what the fields show, which is the
/// half that was still living inside the view. Both directions now answer the same two
/// questions — did the user type something, and is a field showing something older than the
/// record — and every case here fails against one of the shapes that shipped.
@Suite("TaskDrafts")
struct TaskDraftsTests {
    private func task(_ title: String, notes: String = "", id: UUID = UUID()) -> TaskItem {
        var task = TaskItem(id: id)
        task.title = title
        task.notes = notes
        return task
    }

    // MARK: - Loading

    @Test("Loading takes the fields from the task")
    func loadingTakesTheFields() {
        let drafts = TaskDrafts.loaded(from: task("Water the plants", notes: "before winter"))
        #expect(drafts.title == "Water the plants")
        #expect(drafts.notes == "before winter")
    }

    @Test("Freshly loaded fields have nothing to commit")
    func freshDraftsCommitNothing() {
        #expect(TaskDrafts.loaded(from: task("Water the plants")).commit() == nil)
    }

    // MARK: - Resyncing

    @Test("An unfocused field follows a change made elsewhere")
    func unfocusedFieldFollowsTheRecord() {
        // Renaming the row in the list changes the record without changing its id, so nothing
        // reloads the drafts. The field kept the old title, and an edit typed there sent that
        // stale value back as its base — undoing the rename, and trashing the renamed file in
        // markdown mode.
        let original = task("Old")
        let drafts = TaskDrafts.loaded(from: original)
        var renamed = original
        renamed.title = "New"

        let resynced = drafts.resynced(with: renamed, focused: nil)

        #expect(resynced?.title == "New")
        // And nothing to write, because the user typed nothing.
        #expect(resynced?.commit() == nil)
    }

    @Test("A focused field is left alone")
    func focusedFieldIsNotOverwritten() {
        // Resyncing the field being typed into would overwrite the user's text mid-word.
        let original = task("Old")
        let typing = TaskDrafts.loaded(from: original).edited(title: "Old and a half")
        var renamed = original
        renamed.title = "New"

        let resynced = typing.resynced(with: renamed, focused: .title)

        #expect(resynced?.title == "Old and a half")
    }

    @Test("The other field still follows while one is focused")
    func unfocusedSiblingStillFollows() {
        let original = task("Old", notes: "old notes")
        let typing = TaskDrafts.loaded(from: original).edited(title: "Old and a half")
        var changed = original
        changed.notes = "new notes"

        let resynced = typing.resynced(with: changed, focused: .title)

        #expect(resynced?.notes == "new notes")
        #expect(resynced?.title == "Old and a half")
    }

    @Test("A record from a different row is refused")
    func resyncRefusesAnotherRow() {
        // SwiftUI does not document the order sibling onChange actions fire in. If the
        // selection change is delivered before the id handler reloads, the resync must not run
        // against the incoming row — that is how the outgoing row's text reached the wrong task.
        let drafts = TaskDrafts.loaded(from: task("Old"))
        #expect(drafts.resynced(with: task("Another row entirely"), focused: nil) == nil)
    }

    @Test("An unchanged record produces no resync")
    func unchangedRecordIsANoOp() {
        // Returned as nil rather than an equal value, so the view cannot write state for a
        // no-op and re-enter its own update.
        let original = task("Old")
        let drafts = TaskDrafts.loaded(from: original)
        #expect(drafts.resynced(with: original, focused: nil) == nil)
    }

    // MARK: - Committing

    @Test("Typing produces a commit for the row it was typed into")
    func typingCommitsToItsOwnRow() {
        let original = task("Old")
        let drafts = TaskDrafts.loaded(from: original).edited(title: "New")

        let commit = drafts.commit()

        #expect(commit?.taskID == original.id)
        #expect(commit?.title == "New")
        #expect(commit?.notes == nil)
    }

    @Test("A committed edit is not sent twice")
    func committedEditIsNotResent() {
        let drafts = TaskDrafts.loaded(from: task("Old")).edited(title: "New")
        guard let commit = drafts.commit() else {
            Issue.record("an edited draft should produce a commit")
            return
        }

        #expect(drafts.committed(commit).commit() == nil)
    }

    @Test("An edit survives a resync of the other field")
    func editSurvivesAResync() {
        // The sequence that loses data if the resync is too eager: type a title, something
        // changes the notes, then blur. The title edit must still be there to send.
        let original = task("Old", notes: "old notes")
        let typing = TaskDrafts.loaded(from: original).edited(title: "New")
        var changed = original
        changed.notes = "new notes"

        let resynced = typing.resynced(with: changed, focused: .title) ?? typing

        #expect(resynced.commit()?.title == "New")
    }
}
