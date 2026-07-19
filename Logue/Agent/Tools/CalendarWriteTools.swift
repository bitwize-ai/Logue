import Foundation
import MLXLMCommon
import os.log

// MARK: - CreateCalendarEventTool

/// Creates a calendar event via EventKit. Destructive — external side effect in macOS Calendar.
struct CreateCalendarEventTool: AgentTool {
    let name = "create_calendar_event"
    let description = "Create a calendar event in macOS Calendar. Times must be ISO-8601 (e.g. 2026-05-01T14:00:00Z). Requires user approval."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Event title (1-200 chars)"),
                "startISO": AgentToolSpec.stringParam("Start time in ISO-8601 format"),
                "endISO": AgentToolSpec.stringParam("End time in ISO-8601 format (optional — defaults to start+30m)"),
                "notes": AgentToolSpec.stringParam("Event notes (optional, max 2000 chars)"),
            ],
            required: ["title", "startISO"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawTitle = arguments["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let title = String(rawTitle.prefix(200))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            throw AgentToolError.invalidParameter("title", "Title cannot be empty")
        }

        guard let startISO = arguments["startISO"] as? String else {
            throw AgentToolError.missingParameter("startISO")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let backupFormatter = ISO8601DateFormatter()
        backupFormatter.formatOptions = [.withInternetDateTime]

        guard let start = isoFormatter.date(from: startISO) ?? backupFormatter.date(from: startISO) else {
            throw AgentToolError.invalidParameter("startISO", "Unparseable ISO-8601 date: \(startISO)")
        }

        let end: Date
        if let endISO = arguments["endISO"] as? String, !endISO.isEmpty {
            guard let parsed = isoFormatter.date(from: endISO) ?? backupFormatter.date(from: endISO) else {
                throw AgentToolError.invalidParameter("endISO", "Unparseable ISO-8601 date: \(endISO)")
            }
            guard parsed > start else {
                throw AgentToolError.invalidParameter("endISO", "End must be after start")
            }
            end = parsed
        } else {
            end = start.addingTimeInterval(30 * 60)
        }

        let notes: String? = (arguments["notes"] as? String).map { String($0.prefix(2000)) }

        let eventID: String? = await MainActor.run {
            let manager = CalendarManager.shared
            guard manager.isAuthorized else { return nil }
            return manager.createEvent(title: title, startDate: start, endDate: end, notes: notes)
        }

        guard let eventID else {
            return "Calendar access is not granted. The user needs to enable calendar permission in System Settings > Privacy & Security > Calendars."
        }

        return "Created calendar event \"\(title)\" at \(start.formatted(date: .abbreviated, time: .shortened)) (event ID: \(eventID))"
    }
}

// MARK: - UpdateCalendarEventTool

/// Update an existing calendar event by ID. Partial updates supported — pass
/// only the fields the agent wants to change.
struct UpdateCalendarEventTool: AgentTool {
    let name = "update_calendar_event"
    let description = """
    Update an existing macOS Calendar event. Pass the eventID returned by \
    create_calendar_event or get_upcoming_events. Any of title / startISO / \
    endISO / notes may be omitted to keep the existing value.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "eventID": AgentToolSpec.stringParam("EventKit identifier of the event to update"),
                "title": AgentToolSpec.stringParam("New title (optional)"),
                "startISO": AgentToolSpec.stringParam("New ISO-8601 start time (optional)"),
                "endISO": AgentToolSpec.stringParam("New ISO-8601 end time (optional)"),
                "notes": AgentToolSpec.stringParam("New notes (optional, max 2000 chars)"),
            ],
            required: ["eventID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let eventID = (arguments["eventID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !eventID.isEmpty
        else {
            throw AgentToolError.missingParameter("eventID")
        }

        let title = (arguments["title"] as? String)
            .map { String($0.prefix(200)) }?
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let backupFormatter = ISO8601DateFormatter()
        backupFormatter.formatOptions = [.withInternetDateTime]

        let parseISO: (String?) -> Date? = { iso in
            guard let iso, !iso.isEmpty else { return nil }
            return isoFormatter.date(from: iso) ?? backupFormatter.date(from: iso)
        }

        let start = parseISO(arguments["startISO"] as? String)
        let end = parseISO(arguments["endISO"] as? String)
        let notes = (arguments["notes"] as? String).map { String($0.prefix(2000)) }

        do {
            try await MainActor.run {
                try CalendarManager.shared.updateEvent(
                    eventID: eventID,
                    title: title?.isEmpty == false ? title : nil,
                    startDate: start,
                    endDate: end,
                    notes: notes
                )
            }
        } catch CalendarManager.CalendarMutationError.notAuthorized {
            throw AgentToolError.executionFailed("Calendar permission not granted. Approve it in System Settings → Privacy → Calendars.")
        } catch CalendarManager.CalendarMutationError.notFound {
            throw AgentToolError.executionFailed("No calendar event found with ID \(eventID).")
        } catch let CalendarManager.CalendarMutationError.saveFailed(message) {
            throw AgentToolError.executionFailed("Failed to save event: \(message)")
        }

        return "Updated calendar event \(eventID)."
    }
}

// MARK: - DeleteCalendarEventTool

/// Delete a calendar event by its EventKit identifier.
struct DeleteCalendarEventTool: AgentTool {
    let name = "delete_calendar_event"
    let description = "Delete a calendar event by ID. Pass the eventID from create_calendar_event or get_upcoming_events."
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "eventID": AgentToolSpec.stringParam("EventKit identifier of the event to delete"),
            ],
            required: ["eventID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let eventID = (arguments["eventID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !eventID.isEmpty
        else {
            throw AgentToolError.missingParameter("eventID")
        }

        do {
            try await MainActor.run {
                try CalendarManager.shared.deleteEvent(eventID: eventID)
            }
        } catch CalendarManager.CalendarMutationError.notAuthorized {
            throw AgentToolError.executionFailed("Calendar permission not granted.")
        } catch CalendarManager.CalendarMutationError.notFound {
            throw AgentToolError.executionFailed("No calendar event found with ID \(eventID).")
        } catch let CalendarManager.CalendarMutationError.saveFailed(message) {
            throw AgentToolError.executionFailed("Failed to delete event: \(message)")
        }

        return "Deleted calendar event \(eventID)."
    }
}
