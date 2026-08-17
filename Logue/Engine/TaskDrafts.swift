import Foundation

/// The task inspector's free-text fields: what they hold, and what they were loaded from.
///
/// The other half of `TaskTextCommit`. That type moved the *commit* direction out of the view
/// after the rule was got wrong three times running; this moves the *load* direction out for
/// the same reason. Between them a text edit has no state left inside `TaskInspectorPanel` at
/// all: the view holds one of these and reports focus changes and keystrokes into it.
///
/// The two questions this answers are the ones that kept being conflated:
///
/// - **Did the user type something?** Against `loaded`, never against the live record. An edit
///   made elsewhere — renaming the row in the list — changes the record without the user
///   touching the field, and comparing against the record read that as something typed here.
/// - **Is the field showing something older than the record?** Only when the user is not in it.
///   Resyncing a focused field would overwrite what is being typed.
struct TaskDrafts: Equatable {
    /// Which field the user is in, if any. Only these two matter to the drafts.
    enum Field: Equatable {
        case title
        case notes
    }

    /// The task the fields were loaded from, and the values to compare against.
    private(set) var loaded: TaskItem
    private(set) var title: String
    private(set) var notes: String

    /// Fields freshly loaded from a task.
    static func loaded(from task: TaskItem) -> TaskDrafts {
        TaskDrafts(loaded: task, title: task.title, notes: task.notes)
    }

    /// The drafts after the record changed underneath them.
    ///
    /// Returns `nil` when nothing should move, so the caller cannot write state for a no-op.
    /// A record belonging to a different task is refused outright: the resync must not run
    /// against a row that has already been replaced, whatever order SwiftUI delivers its
    /// changes in.
    func resynced(with task: TaskItem, focused: Field?) -> TaskDrafts? {
        guard task.id == loaded.id else { return nil }

        // A field's draft and the base it is measured against move together or not at all.
        // Advancing the base for a focused field — whose draft is deliberately left alone —
        // makes the untouched draft differ from the new base, so the next blur "commits" a value
        // the user never typed and undoes the change that arrived from elsewhere. That is the
        // same defect this type was extracted to end, reintroduced one level down.
        var updated = self
        if focused != .title {
            updated.title = task.title
            updated.loaded.title = task.title
        }
        if focused != .notes {
            updated.notes = task.notes
            updated.loaded.notes = task.notes
        }
        return updated == self ? nil : updated
    }

    /// The drafts with a field edited by the user.
    func edited(title: String? = nil, notes: String? = nil) -> TaskDrafts {
        var updated = self
        if let title {
            updated.title = title
        }
        if let notes {
            updated.notes = notes
        }
        return updated
    }

    /// What to write, or `nil` when the user typed nothing.
    func commit() -> TaskTextCommit? {
        TaskTextCommit.make(loadedFrom: loaded, titleDraft: title, notesDraft: notes)
    }

    /// The drafts after a commit has been sent, so a later blur with nothing further typed
    /// has nothing to send.
    func committed(_ commit: TaskTextCommit) -> TaskDrafts {
        guard let applied = commit.applied(to: loaded) else { return self }
        var updated = self
        updated.loaded = applied
        return updated
    }
}
