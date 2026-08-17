import Foundation

/// What a text edit in the task inspector should write, and to which task.
///
/// This rule has been got wrong three times running, and every time because it lived inside a
/// SwiftUI view where nothing could test it. The three defects were all the same shape — a
/// commit carrying a value the user did not type:
///
/// 1. Built from the live record while the selection had already moved, so the outgoing row's
///    title landed on the newly-selected one, renaming its file and trashing the original.
/// 2. Built from a snapshot taken at selection, so it put back every field changed since — a
///    due date, a priority, a tag, or the list row's completion tick with its `completedCount`.
/// 3. Guarded on "either field differs" and then sending both, so typing a note re-sent a stale
///    title and destroyed a rename made in the list row.
///
/// So the decision is made here instead, as a value: which task, and which fields actually
/// changed. A field the user did not touch is `nil` and is never written. The view keeps only
/// the drafts and the values it loaded them with.
struct TaskTextCommit: Equatable {
    /// The task the text was typed into — carried so the commit cannot be applied to whatever
    /// row happens to be selected when it lands.
    let taskID: UUID
    /// The new title, or `nil` when the title was not edited.
    let title: String?
    /// The new notes, or `nil` when the notes were not edited.
    let notes: String?

    /// The commit for these drafts, or `nil` when nothing was typed.
    ///
    /// - Parameters:
    ///   - loaded: the task the fields were loaded from, and the values to compare against.
    ///     Compared against these rather than against the live record because an edit made
    ///     elsewhere — a rename in the list row — would otherwise read as something typed here.
    ///   - titleDraft: what the title field holds now, before sanitising.
    ///   - notesDraft: what the notes field holds now.
    static func make(loadedFrom loaded: TaskItem, titleDraft: String, notesDraft: String) -> TaskTextCommit? {
        let sanitised = TaskTextParser.sanitisedTitle(titleDraft)
        let title = sanitised == loaded.title ? nil : sanitised
        let notes = notesDraft == loaded.notes ? nil : notesDraft

        guard title != nil || notes != nil else { return nil }
        return TaskTextCommit(taskID: loaded.id, title: title, notes: notes)
    }

    /// Applies the commit to a task, leaving untouched fields alone.
    ///
    /// Refuses a task it was not made for: the commit travels with an id precisely so that a
    /// caller holding the wrong record cannot silently write to it.
    func applied(to task: TaskItem) -> TaskItem? {
        guard task.id == taskID else { return nil }
        var updated = task
        if let title {
            updated.title = title
        }
        if let notes {
            updated.notes = notes
        }
        return updated
    }
}
