import Foundation
import MLXLMCommon
import os.log

// MARK: - ListMeetingsTool

/// Lists all active (non-trashed) meetings with title, date, duration, and action item count.
struct ListMeetingsTool: AgentTool {
    let name = "list_meetings"
    let description = "List all meetings with their titles, dates, and summary info."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["limit": AgentToolSpec.intParam("Maximum meetings to return (default 15, max 30)")]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let limit = min((arguments["limit"] as? Int) ?? 15, 30)
        let (allCount, meetings) = await MainActor.run {
            let active = MeetingStore.shared.activeMeetings
            let sorted = Array(active.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
            return (active.count, sorted)
        }

        guard !meetings.isEmpty else {
            return "No meetings found."
        }

        var output = "\(allCount) meeting(s) total"
        if allCount > limit {
            output += " (showing most recent \(limit))"
        }
        output += ":\n"

        for (index, meeting) in meetings.enumerated() {
            let duration = Int(meeting.duration / 60)
            output += "\n\(index + 1). \(meeting.title)"
            output += "\n   ID: \(meeting.id.uuidString)"
            output += "\n   Date: \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))"
            output += "\n   Duration: \(duration)m"
            if !meeting.actionItems.isEmpty {
                let pending = meeting.actionItems.filter { !$0.isCompleted }.count
                output += " | Action items: \(meeting.actionItems.count) (\(pending) pending)"
            }
        }
        return output
    }
}

// MARK: - SearchMeetingsTool

/// Full-text search across all meetings using the FTS5 index.
struct SearchMeetingsTool: AgentTool {
    let name = "search_meetings"
    let description = "Search meetings by keyword or topic."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "query": AgentToolSpec.stringParam("Search keywords"),
                "limit": AgentToolSpec.intParam("Maximum results (default 5, max 10)"),
            ],
            required: ["query"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = min((arguments["limit"] as? Int) ?? 5, 10)

        let results = await MeetingMemoryIndex.shared.search(query: query, limit: limit)

        guard !results.isEmpty else {
            return "No meetings found matching \"\(query)\"."
        }

        var output = "Found \(results.count) meeting(s) matching \"\(query)\":\n"
        for (index, result) in results.enumerated() {
            output += "\n\(index + 1). \(result.title)"
            output += "\n   ID: \(result.meetingID.uuidString)"
            if !result.summarySnippet.isEmpty {
                output += "\n   Summary: \(String(result.summarySnippet.prefix(120)))"
            } else if !result.transcriptSnippet.isEmpty {
                output += "\n   Snippet: \(String(result.transcriptSnippet.prefix(120)))"
            }
        }
        return output
    }
}

// MARK: - GetMeetingDetailsTool

/// Retrieves full details for a specific meeting by ID.
struct GetMeetingDetailsTool: AgentTool {
    let name = "get_meeting_details"
    let description = "Get full details of a specific meeting by ID."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["meetingID": AgentToolSpec.stringParam("UUID of the meeting")],
            required: ["meetingID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["meetingID"] as? String,
              let meetingID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("meetingID")
        }

        let meeting: MeetingNote = try await MainActor.run {
            let store = MeetingStore.shared
            guard let index = store.meetingIndex(for: meetingID) else {
                throw AgentToolError.meetingNotFound(idString)
            }
            return store.meetings[index]
        }

        var output = "Meeting: \(meeting.title)\n"
        output += "Date: \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
        output += "Duration: \(formatDuration(meeting.duration))\n"

        if !meeting.speakers.isEmpty {
            output += "Speakers: \(meeting.speakers.map(\.name).joined(separator: ", "))\n"
        }

        if !meeting.topicKeywords.isEmpty {
            output += "Keywords: \(meeting.topicKeywords.joined(separator: ", "))\n"
        }

        if let summary = meeting.summary, !summary.isEmpty {
            output += "\nSummary: \(String(summary.prefix(500)))\n"
        }

        if !meeting.actionItems.isEmpty {
            output += "\nAction Items (\(meeting.actionItems.count)):\n"
            for (idx, item) in meeting.actionItems.enumerated() {
                let status = item.isCompleted ? "[Done]" : "[Pending]"
                output += "  \(idx + 1). \(status) \(item.title)"
                if let assignee = item.assignee {
                    output += " — \(assignee)"
                }
                if let due = item.dueDescription {
                    output += " (due: \(due))"
                }
                output += "\n"
            }
        }

        if let smartMinutes = meeting.smartMinutes, !smartMinutes.keyDecisions.isEmpty {
            output += "\nKey Decisions:\n"
            for decision in smartMinutes.keyDecisions {
                output += "  - \(decision)\n"
            }
        }

        return output
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - GetTranscriptTool

/// Returns the full speaker-tagged transcript for a meeting, up to a char budget.
struct GetTranscriptTool: AgentTool {
    let name = "get_transcript"
    let description = """
    Get the full speaker-tagged transcript of a specific meeting. \
    Use when a user asks what was said, who said what, or wants direct quotes.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "meetingID": AgentToolSpec.stringParam("UUID of the meeting"),
                "maxChars": AgentToolSpec.intParam("Maximum transcript characters to return (default 4000)"),
            ],
            required: ["meetingID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["meetingID"] as? String,
              let meetingID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("meetingID")
        }
        let maxChars = min(
            (arguments["maxChars"] as? Int) ?? AppConstants.AgentDefaults.toolResultMaxChars,
            AppConstants.AgentDefaults.toolResultMaxChars
        )

        let meeting: MeetingNote = try await MainActor.run {
            let store = MeetingStore.shared
            guard let index = store.meetingIndex(for: meetingID) else {
                throw AgentToolError.meetingNotFound(idString)
            }
            return store.meetings[index]
        }

        guard !meeting.segments.isEmpty else {
            return "Meeting \"\(meeting.title)\" has no transcript segments."
        }

        // Build speaker-tagged lines
        let speakerByLabel = Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0.name) })
        var formatted = "Transcript: \(meeting.title)\n"
        formatted += "Date: \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"

        var body = ""
        for segment in meeting.segments {
            let speaker = segment.speakerLabel.flatMap { speakerByLabel[$0] } ?? segment.speakerLabel ?? "Speaker"
            let timestamp = formatTimestamp(segment.startTime)
            body += "[\(timestamp)] \(speaker): \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }

        let truncated = String(body.prefix(maxChars))
        formatted += "<transcript>\n\(truncated)\n</transcript>"
        if body.count > maxChars {
            formatted += "\n\n[Transcript truncated — showing first \(maxChars) of \(body.count) characters]"
        }
        return formatted
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - GetActionItemsTool

/// Retrieves action items across all meetings with filtering.
struct GetActionItemsTool: AgentTool {
    let name = "get_action_items"
    let description = "Get action items from meetings. Filter by status: pending, overdue, completed, or all."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "status": AgentToolSpec.stringParam(
                    "Filter by status",
                    enumValues: ["pending", "overdue", "completed", "all"]
                ),
                "meetingID": AgentToolSpec.stringParam("Optional meeting UUID to scope the query"),
            ]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let meetings = try await fetchMeetings(from: arguments)
        let statusFilter = (arguments["status"] as? String)?.lowercased() ?? "all"

        var items = collectItems(from: meetings, statusFilter: statusFilter)

        guard !items.isEmpty else {
            return "No \(statusFilter == "all" ? "" : statusFilter + " ")action items found."
        }

        items.sort { lhs, rhs in
            if !lhs.item.isCompleted, rhs.item.isCompleted {
                return true
            }
            if lhs.item.isCompleted, !rhs.item.isCompleted {
                return false
            }
            if let lhsDue = lhs.item.dueDate, let rhsDue = rhs.item.dueDate {
                return lhsDue < rhsDue
            }
            if lhs.item.dueDate != nil {
                return true
            }
            return false
        }

        return formatItems(items, statusFilter: statusFilter)
    }

    private func fetchMeetings(from arguments: [String: Any]) async throws -> [MeetingNote] {
        try await MainActor.run {
            let store = MeetingStore.shared
            if let idString = arguments["meetingID"] as? String,
               let meetingID = UUID(uuidString: idString)
            {
                guard let index = store.meetingIndex(for: meetingID) else {
                    throw AgentToolError.meetingNotFound(idString)
                }
                return [store.meetings[index]]
            }
            return store.activeMeetings
        }
    }

    private func collectItems(
        from meetings: [MeetingNote],
        statusFilter: String
    ) -> [(meeting: MeetingNote, item: ActionItem)] {
        let now = Date.now
        var items: [(meeting: MeetingNote, item: ActionItem)] = []
        for meeting in meetings {
            for item in meeting.actionItems {
                let isOverdue = !item.isCompleted && (item.dueDate.map { $0 < now } ?? false)
                let include = switch statusFilter {
                case "pending": !item.isCompleted
                case "overdue": isOverdue
                case "completed": item.isCompleted
                default: true
                }
                if include {
                    items.append((meeting: meeting, item: item))
                }
            }
        }
        return items
    }

    private func formatItems(
        _ items: [(meeting: MeetingNote, item: ActionItem)],
        statusFilter: String
    ) -> String {
        let label = statusFilter == "all" ? "" : " \(statusFilter)"
        var output = "\(items.count)\(label) action item(s):\n"
        for (index, entry) in items.prefix(20).enumerated() {
            let status = entry.item.isCompleted ? "[Done]" : "[Pending]"
            let isOverdue = !entry.item.isCompleted && (entry.item.dueDate.map { $0 < .now } ?? false)
            output += "\n\(index + 1). \(status) \(entry.item.title)"
            output += "\n   From: \(entry.meeting.title)"
            if let assignee = entry.item.assignee {
                output += "\n   Assigned: \(assignee)"
            }
            if let due = entry.item.dueDescription {
                output += "\n   Due: \(due)"
            }
            if isOverdue {
                output += " *** OVERDUE ***"
            }
        }
        if items.count > 20 {
            output += "\n\n... and \(items.count - 20) more."
        }
        return output
    }
}

// MARK: - GetDailyDigestTool

/// Summarizes meetings for a given date (default: today).
struct GetDailyDigestTool: AgentTool {
    let name = "get_daily_digest"
    let description = "Get a summary of all meetings from a specific date. Defaults to today."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["date": AgentToolSpec.stringParam("Date in YYYY-MM-DD format (default: today)")]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let targetDate: Date
        if let dateString = arguments["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let parsed = formatter.date(from: dateString) else {
                throw AgentToolError.invalidParameter("date", "Expected format: YYYY-MM-DD")
            }
            targetDate = parsed
        } else {
            targetDate = .now
        }

        let calendar = Calendar.current
        let dayMeetings = await MainActor.run {
            MeetingStore.shared.activeMeetings.filter { meeting in
                calendar.isDate(meeting.createdAt, inSameDayAs: targetDate)
            }
        }

        let dateStr = targetDate.formatted(date: .abbreviated, time: .omitted)

        guard !dayMeetings.isEmpty else {
            return "No meetings recorded on \(dateStr)."
        }

        var totalDuration: TimeInterval = 0
        var allActionItems: [ActionItem] = []

        var output = "\(dayMeetings.count) meeting(s) on \(dateStr):\n"

        for (index, meeting) in dayMeetings.enumerated() {
            totalDuration += meeting.duration
            allActionItems.append(contentsOf: meeting.actionItems)

            output += "\n\(index + 1). \(meeting.title) (\(Int(meeting.duration / 60))m)"
            if let summary = meeting.summary {
                output += "\n   Summary: \(String(summary.prefix(150)))"
            }
            if !meeting.actionItems.isEmpty {
                output += "\n   Action items: \(meeting.actionItems.count)"
            }
        }

        let pending = allActionItems.filter { !$0.isCompleted }
        output += "\n\nTotal: \(Int(totalDuration / 60))m meeting time, \(allActionItems.count) action items (\(pending.count) pending)"

        return output
    }
}
