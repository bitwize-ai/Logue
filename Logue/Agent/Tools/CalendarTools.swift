import Foundation
import MLXLMCommon
import os.log

// MARK: - GetUpcomingEventsTool

/// Retrieves upcoming calendar events via the native EventKit integration.
struct GetUpcomingEventsTool: AgentTool {
    let name = "get_upcoming_events"
    let description = "Get upcoming calendar events for the next N days. Requires calendar access permission."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["days": AgentToolSpec.intParam("Days to look ahead (default 3, max 14)")]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let days = min((arguments["days"] as? Int) ?? 3, 14)

        let (isEnabled, events) = await MainActor.run {
            let calendarManager = CalendarManager.shared
            let startDate = Date.now
            let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
            return (calendarManager.isEnabled, calendarManager.events(from: startDate, to: endDate))
        }

        guard isEnabled else {
            return "Calendar access is not enabled. The user needs to grant calendar permission in System Settings > Privacy & Security > Calendars."
        }

        guard !events.isEmpty else {
            return "No upcoming calendar events in the next \(days) day(s)."
        }

        var output = "\(events.count) upcoming event(s) in the next \(days) day(s):\n\n"
        for (index, event) in events.enumerated() {
            output += "[\(index + 1)] \(event.title)\n"
            output += "    Start: \(event.startDate.formatted(date: .abbreviated, time: .shortened))\n"
            output += "    End: \(event.endDate.formatted(date: .abbreviated, time: .shortened))\n"
            if let location = event.location, !location.isEmpty {
                output += "    Location: \(location)\n"
            }
            if let calName = event.calendarName {
                output += "    Calendar: \(calName)\n"
            }
            output += "\n"
        }

        return output
    }
}
