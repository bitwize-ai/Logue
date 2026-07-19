import EventKit
import Foundation
import MLXLMCommon

// MARK: - Shared EventKit access

private enum RemindersAccess {
    /// EventKit reminders + calendars share an `EKEventStore` instance, but
    /// have separate authorization. Keep one process-wide store.
    static let store = EKEventStore()

    /// Requests reminders permission. Idempotent if already granted.
    static func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                return try await store.requestFullAccessToReminders()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - GetRemindersTool

/// Reads reminders from the user's macOS Reminders app via EventKit.
/// Read-only. `.regular` clearance — no mutation, just listing.
struct GetRemindersTool: AgentTool {
    let name = "get_reminders"
    let description = """
    List the user's reminders. Returns title, due date, completion status, \
    and priority. Filter by completion (default: incomplete only) or by \
    keyword in the title.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "include_completed": AgentToolSpec.stringParam(
                    "Set to 'true' to also include completed reminders. Default: false."
                ),
                "query": AgentToolSpec.stringParam("Optional substring filter on the title"),
                "limit": AgentToolSpec.intParam("Maximum results (default 20, max 50)"),
            ]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let includeCompleted = (arguments["include_completed"] as? String)?.lowercased() == "true"
        let query = (arguments["query"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let limit = min((arguments["limit"] as? Int) ?? 20, 50)

        guard await RemindersAccess.requestAccess() else {
            throw AgentToolError.executionFailed("Reminders access not granted. Approve it in System Settings → Privacy → Reminders.")
        }

        let predicate: NSPredicate = if includeCompleted {
            RemindersAccess.store.predicateForReminders(in: nil)
        } else {
            RemindersAccess.store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
        }

        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            RemindersAccess.store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }

        var filtered = reminders
        if !query.isEmpty {
            filtered = filtered.filter { ($0.title ?? "").lowercased().contains(query) }
        }
        // Sort: incomplete due-soonest first, then by title.
        filtered.sort { lhs, rhs -> Bool in
            switch (lhs.dueDateComponents?.date, rhs.dueDateComponents?.date) {
            case let (.some(left), .some(right)): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return (lhs.title ?? "") < (rhs.title ?? "")
            }
        }
        let trimmed = Array(filtered.prefix(limit))
        guard !trimmed.isEmpty else {
            return query.isEmpty ? "No reminders found." : "No reminders matched \"\(query)\"."
        }

        var output = "Found \(trimmed.count) reminder(s):\n"
        for (idx, reminder) in trimmed.enumerated() {
            output += "\n\(idx + 1). \(reminder.title ?? "(untitled)")"
            if reminder.isCompleted {
                output += " ✓"
            }
            if let due = reminder.dueDateComponents?.date {
                output += " — due \(due.formatted(date: .abbreviated, time: .shortened))"
            }
            if reminder.priority > 0 {
                output += " [priority \(reminder.priority)]"
            }
            // Surface the EventKit ID so the agent can call update/delete
            // tools without a second lookup round-trip.
            output += "\n   id: \(reminder.calendarItemIdentifier)"
            if let notes = reminder.notes, !notes.isEmpty {
                output += "\n   \(String(notes.prefix(120)))"
            }
        }
        return output
    }
}

// MARK: - AddReminderTool

/// Creates a reminder in the user's default Reminders list.
/// `.sensitive` clearance — mutation that the user should approve.
struct AddReminderTool: AgentTool {
    let name = "add_reminder"
    let description = """
    Create a new reminder in the user's default Reminders list. Requires a \
    title; optionally accepts a due date (ISO-8601, e.g. "2025-12-31T17:00:00Z") \
    and notes.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Reminder title (required, 1-200 chars)"),
                "due_date_iso": AgentToolSpec.stringParam(
                    "Due date in ISO-8601 format (e.g. \"2025-12-31T17:00:00Z\"). Optional."
                ),
                "notes": AgentToolSpec.stringParam("Optional notes / description"),
            ],
            required: ["title"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawTitle = arguments["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let title = String(rawTitle.prefix(200))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw AgentToolError.invalidParameter("title", "Title cannot be empty")
        }

        guard await RemindersAccess.requestAccess() else {
            throw AgentToolError.executionFailed("Reminders access not granted. Approve it in System Settings → Privacy → Reminders.")
        }

        let store = RemindersAccess.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = title

        if let notes = (arguments["notes"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty
        {
            reminder.notes = String(notes.prefix(2000))
        }

        if let isoString = (arguments["due_date_iso"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !isoString.isEmpty
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let due = formatter.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString)
            {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: due
                )
            }
        }

        // Default Reminders calendar — Apple guarantees one exists once
        // permission is granted.
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw AgentToolError.executionFailed("No default Reminders list found.")
        }
        reminder.calendar = calendar

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw AgentToolError.executionFailed("Failed to save reminder: \(error.localizedDescription)")
        }

        var output = "Reminder created: \"\(title)\""
        if let due = reminder.dueDateComponents?.date {
            output += " — due \(due.formatted(date: .abbreviated, time: .shortened))"
        }
        return output
    }
}

// MARK: - UpdateReminderTool

/// Update an existing reminder by EventKit identifier. Partial updates supported.
struct UpdateReminderTool: AgentTool {
    let name = "update_reminder"
    let description = """
    Update an existing reminder. Pass the reminderID returned by get_reminders. \
    Any of title / due_date_iso / notes / completed may be omitted to keep the \
    existing value.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "reminderID": AgentToolSpec.stringParam("EventKit identifier of the reminder"),
                "title": AgentToolSpec.stringParam("New title (optional)"),
                "due_date_iso": AgentToolSpec.stringParam("New due date in ISO-8601 (optional). Pass empty string to clear."),
                "notes": AgentToolSpec.stringParam("New notes (optional, max 2000 chars)"),
                "completed": AgentToolSpec.stringParam("Set to 'true' to mark complete, 'false' to mark incomplete"),
            ],
            required: ["reminderID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let reminderID = (arguments["reminderID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !reminderID.isEmpty
        else {
            throw AgentToolError.missingParameter("reminderID")
        }

        guard await RemindersAccess.requestAccess() else {
            throw AgentToolError.executionFailed("Reminders access not granted.")
        }

        let store = RemindersAccess.store
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AgentToolError.executionFailed("No reminder found with ID \(reminderID).")
        }

        if let rawTitle = (arguments["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty
        {
            reminder.title = String(rawTitle.prefix(200))
                .filter { !$0.isNewline && $0.asciiValue != 0 }
        }

        if let rawNotes = arguments["notes"] as? String {
            reminder.notes = rawNotes.isEmpty ? nil : String(rawNotes.prefix(2000))
        }

        if let isoString = arguments["due_date_iso"] as? String {
            if isoString.isEmpty {
                reminder.dueDateComponents = nil
            } else {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                if let due = formatter.date(from: isoString)
                    ?? ISO8601DateFormatter().date(from: isoString)
                {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: due
                    )
                }
            }
        }

        if let completedRaw = (arguments["completed"] as? String)?.lowercased() {
            switch completedRaw {
            case "true", "yes", "1":
                reminder.isCompleted = true
                reminder.completionDate = .now
            case "false", "no", "0":
                reminder.isCompleted = false
                reminder.completionDate = nil
            default: break
            }
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw AgentToolError.executionFailed("Failed to save reminder: \(error.localizedDescription)")
        }

        return "Updated reminder \"\(reminder.title ?? "(untitled)")\"."
    }
}

// MARK: - DeleteReminderTool

/// Delete a reminder by EventKit identifier.
struct DeleteReminderTool: AgentTool {
    let name = "delete_reminder"
    let description = "Delete a reminder by ID. Pass the reminderID from get_reminders."
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "reminderID": AgentToolSpec.stringParam("EventKit identifier of the reminder to delete"),
            ],
            required: ["reminderID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let reminderID = (arguments["reminderID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !reminderID.isEmpty
        else {
            throw AgentToolError.missingParameter("reminderID")
        }

        guard await RemindersAccess.requestAccess() else {
            throw AgentToolError.executionFailed("Reminders access not granted.")
        }

        let store = RemindersAccess.store
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AgentToolError.executionFailed("No reminder found with ID \(reminderID).")
        }

        do {
            try store.remove(reminder, commit: true)
        } catch {
            throw AgentToolError.executionFailed("Failed to delete reminder: \(error.localizedDescription)")
        }

        return "Deleted reminder \(reminderID)."
    }
}
