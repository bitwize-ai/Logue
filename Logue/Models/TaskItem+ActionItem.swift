import Foundation

extension TaskItem {
    /// A task promoted from a meeting's action item.
    ///
    /// A copy, not a move: the action item stays on the meeting and stays checkable there.
    /// The meeting is a record of what was said, and editing that record because the user
    /// later reprioritised a task would be rewriting history.
    ///
    /// The task **reuses the action item's identifier**. That makes re-promotion a lookup
    /// rather than a second bookkeeping field, which matters because "Add all to Tasks" is a
    /// button people press twice.
    init(actionItem: ActionItem, meetingID: UUID, now: Date = .now) {
        self.init(
            id: actionItem.id,
            title: TaskTextParser.sanitisedTitle(actionItem.title),
            status: actionItem.isCompleted ? .done : .todo,
            // Medium, because the model did not rank it. Inventing urgency here would put a
            // made-up priority on every promoted item.
            priority: .medium,
            dueDate: actionItem.dueDate,
            recurrence: nil,
            createdAt: actionItem.createdAt,
            updatedAt: now,
            sourceMeetingID: meetingID,
            notes: Self.carriedNotes(from: actionItem)
        )
    }

    /// What the action item holds that a task has no field for.
    ///
    /// Written into the body rather than dropped: `assignee` is meaningful in a meeting with
    /// attendees, and `dueDescription` is often the only record of "before the board meeting"
    /// when no date could be resolved. Losing either silently would make promotion feel lossy
    /// in exactly the cases where the model did well.
    fileprivate static func carriedNotes(from actionItem: ActionItem) -> String {
        var lines: [String] = []
        if let assignee = actionItem.assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assignee.isEmpty
        {
            lines.append("Assigned to: \(assignee)")
        }
        // Only when no real date resolved it — otherwise the badge and the note say the same
        // thing, and the note is the vaguer of the two.
        if let description = actionItem.dueDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !description.isEmpty, actionItem.dueDate == nil
        {
            lines.append("Due: \(description)")
        }
        return lines.joined(separator: "\n")
    }
}

extension TaskStore {
    /// The task a given action item was promoted into, if any.
    ///
    /// By identifier, because promotion reuses it.
    func promotedTask(for actionItemID: UUID) -> TaskItem? {
        task(id: actionItemID)
    }

    /// Promotes an action item, or updates the task it already produced.
    ///
    /// Idempotent on purpose: pressing "Add All to Tasks" twice must not double the list.
    @discardableResult
    func promote(_ actionItem: ActionItem, from meetingID: UUID) -> TaskItem {
        if let existing = promotedTask(for: actionItem.id) {
            let merged = Self.merging(actionItem, into: existing)
            update(merged)
            return merged
        }
        let task = TaskItem(actionItem: actionItem, meetingID: meetingID)
        add(task)
        return task
    }

    /// Folds a re-read action item into the task it already produced.
    ///
    /// Additive only. By this point the task is the user's copy — they may have reprioritised
    /// it, tagged it, completed it, or written their own notes — so a re-promotion fills gaps
    /// and never overwrites. The one thing it takes is a due date the meeting has gained and
    /// the task does not, because that is new information rather than a competing opinion.
    nonisolated static func merging(
        _ actionItem: ActionItem, into existing: TaskItem, now: Date = .now
    ) -> TaskItem {
        var merged = existing
        merged.updatedAt = now
        if merged.dueDate == nil {
            merged.dueDate = actionItem.dueDate
        }
        if merged.notes.isEmpty {
            // The helper directly, rather than building a whole throwaway task around a
            // fabricated meeting identifier just to read one string off it.
            merged.notes = TaskItem.carriedNotes(from: actionItem)
        }
        return merged
    }
}
