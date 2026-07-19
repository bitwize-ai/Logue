import Foundation
import os.log

/// Builds prompts for meeting analysis — Smart Minutes, action items, and chat.
enum MeetingPromptBuilder {
    // MARK: - Summary Prompt

    /// System-level instructions for meeting summary generation (JSON format, rules, template guidance).
    /// Sourced from `PromptRegistry.Meeting.summaryInstructions`.
    static func summarySystemInstructions(template: MeetingTemplate = .general) -> String {
        PromptRegistry.Meeting.summaryInstructions(template: template)
    }

    /// Prompt-level content for meeting summary generation (question + labeled transcript).
    static func summaryPrompt(transcript: String) -> String {
        """
        Produce a structured JSON summary for this meeting.

        ---

        <transcript>
        \(transcript)
        </transcript>
        """
    }

    /// Returns template-specific instructions to append to the summary prompt.
    /// Sourced from `PromptRegistry.Meeting.templateInstructions`.
    private static func templateInstructions(for template: MeetingTemplate) -> String {
        PromptRegistry.Meeting.templateInstructions(for: template)
    }

    // MARK: - Chat Prompt

    /// Whether a user question references past/other meetings (triggers cross-meeting context).
    static func referencesPastMeetings(_ question: String) -> Bool {
        let lowered = question.lowercased()
        let triggers = [
            "last time", "last meeting", "previous meeting", "past meeting",
            "other meeting", "before", "earlier", "previously", "last week",
            "follow up", "follow-up", "carried over", "recurring",
            "we discussed", "we talked", "we agreed", "mentioned before",
        ]
        return triggers.contains { lowered.contains($0) }
    }

    static func buildChatPrompt(
        question: String,
        transcript: String,
        summary: String?,
        actionItems: [ActionItem] = [],
        crossMeetingContext: String? = nil
    ) -> String {
        var parts: [String] = []

        // Put the question first so the model knows what to look for in the context
        parts.append("QUESTION: \(question)")
        parts.append("Answer ONLY the question above. Do NOT summarize the whole meeting.")

        // Always include transcript — this is the primary source for Q&A.
        if !transcript.isEmpty {
            parts.append("FULL TRANSCRIPT:\n<transcript>\n\(transcript)\n</transcript>")
        }

        // Summary as supplementary context
        if let summary, !summary.isEmpty {
            parts.append("MEETING SUMMARY:\n\(summary)")
        }

        if !actionItems.isEmpty {
            let items = actionItems.prefix(10).map(\.title).joined(separator: "; ")
            parts.append("ACTION ITEMS: \(items)")
        }

        if let crossMeetingContext, !crossMeetingContext.isEmpty {
            parts.append(crossMeetingContext)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Cross-Meeting Search Prompt

    /// System instructions for cross-meeting search.
    /// Sourced from `PromptRegistry.Meeting.searchSystem`.
    static let searchSystemInstructions = PromptRegistry.Meeting.searchSystem.content

    static func buildSearchPrompt(query: String, meetingSummaries: [(title: String, summary: String)]) -> String {
        let context = meetingSummaries.map { meeting in
            let safeTitle = String(meeting.title.prefix(200))
            return "## \(safeTitle)\n<content>\n\(meeting.summary)\n</content>"
        }.joined(separator: "\n\n---\n\n")

        return """
        \(query)

        ---

        MEETING SUMMARIES:
        \(context)
        """
    }

    // MARK: - Daily Digest Prompt

    static func buildDailyDigestPrompt(meetings: [(title: String, summary: String, actionItemCount: Int, pendingCount: Int)]) -> String {
        let meetingList = meetings.enumerated().map { index, meeting in
            """
            Meeting \(index + 1): \(meeting.title)
            Summary: \(meeting.summary)
            Action Items: \(meeting.actionItemCount) total, \(meeting.pendingCount) pending
            """
        }.joined(separator: "\n\n")

        return """
        Based on today's meetings, generate a daily digest. \
        Output ONLY a single line of compact JSON — no markdown, no code fences, no extra text.

        Required JSON format:
        {"headline":"Brief summary","totalMeetingTime":"2h 15m across 3 meetings",\
        "keyHighlights":["Point 1","Point 2","Point 3"],\
        "pendingActions":["Action 1","Action 2"],"tomorrowFocus":"Focus suggestion"}

        Rules:
        - headline: one brief sentence summarizing the day
        - keyHighlights: 3-5 most important points across ALL meetings
        - pendingActions: top pending action items needing attention
        - tomorrowFocus: one suggestion for tomorrow
        - Be concise — this is a quick daily overview

        TODAY'S MEETINGS:
        \(meetingList)
        """
    }

    /// Parse the daily digest JSON from LLM response.
    static func parseDailyDigest(from response: String) -> DailyDigest? {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8)
        else { return nil }

        struct RawDigest: Decodable {
            var headline: String?
            var totalMeetingTime: String?
            var keyHighlights: [String]?
            var pendingActions: [String]?
            var tomorrowFocus: String?
        }

        guard let raw = try? JSONDecoder().decode(RawDigest.self, from: data) else { return nil }

        return DailyDigest(
            headline: raw.headline ?? "Your daily meeting summary",
            totalMeetingTime: raw.totalMeetingTime ?? "",
            keyHighlights: raw.keyHighlights ?? [],
            pendingActions: raw.pendingActions ?? [],
            tomorrowFocus: raw.tomorrowFocus
        )
    }

    // MARK: - Parsing

    /// Extract the outermost JSON object from a response, handling braces inside strings.
    private static func extractJSON(from response: String) -> String? {
        // Strip markdown code fences (```json ... ```) that small models often add
        var cleaned = response
        if let fenceStart = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
            if let fenceEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
        }
        guard let jsonStart = cleaned.firstIndex(of: "{") else { return nil }

        var depth = 0
        var jsonEnd = jsonStart
        var inString = false
        var prevChar: Character = " "

        for index in cleaned[jsonStart...].indices {
            let char = cleaned[index]

            if char == "\"", prevChar != "\\" {
                inString.toggle()
            }

            if !inString {
                if char == "{" {
                    depth += 1
                }
                if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = index
                        break
                    }
                }
            }
            prevChar = char
        }

        guard depth == 0 else { return nil }
        return String(cleaned[jsonStart ... jsonEnd])
    }

    // MARK: - Smart Highlights

    /// Builds the user prompt containing the timestamped transcript for highlight extraction.
    /// Each segment is prefixed with `[NNN]` where `NNN` is the start time in seconds,
    /// so the LLM can attribute each highlight to an exact moment.
    static func highlightsPrompt(segments: [TranscriptSegment], maxChars: Int) -> String {
        var lines: [String] = []
        var used = 0
        let header = "Extract 5-10 Smart Highlights from this timestamped transcript."
        let footer = "</transcript>"
        let wrapperOverhead = header.count + "\n\n<transcript>\n".count + footer.count

        for segment in segments {
            let ts = Int(segment.startTime.rounded())
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let line = "[\(ts)] \(text)"
            // Keep a safety margin below the caller-provided maxChars
            if used + line.count + wrapperOverhead > maxChars {
                break
            }
            lines.append(line)
            used += line.count + 1 // + newline
        }

        return """
        \(header)

        <transcript>
        \(lines.joined(separator: "\n"))
        \(footer)
        """
    }

    /// Parse the JSON array returned by the highlights prompt. Silently drops malformed entries
    /// and items whose timestamp falls outside the meeting's duration.
    static func parseHighlights(from response: String, meetingDuration: TimeInterval) -> [Bookmark] {
        guard let jsonString = extractJSONArray(from: response),
              let data = jsonString.data(using: .utf8)
        else { return [] }

        struct RawHighlight: Decodable {
            var timestamp: Double
            var label: String
            var color: String?
        }

        let raw: [RawHighlight]
        do {
            raw = try JSONDecoder().decode([RawHighlight].self, from: data)
        } catch {
            let logger = Logger(subsystem: AppConstants.bundleID, category: "MeetingPromptBuilder")
            logger.warning("Highlights JSON decode failed: \(error.localizedDescription, privacy: .public)")
            logger.debug("Raw JSON (truncated): \(jsonString.prefix(500), privacy: .private)")
            return []
        }

        let maxLabelLength = 80
        return raw.compactMap { item -> Bookmark? in
            // Drop out-of-range timestamps — protects against LLM hallucination.
            guard item.timestamp >= 0, item.timestamp <= meetingDuration + 5 else { return nil }
            let trimmed = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let clipped = trimmed.count > maxLabelLength
                ? String(trimmed.prefix(maxLabelLength))
                : trimmed
            let color = BookmarkColor(rawValue: item.color?.lowercased() ?? "") ?? .blue
            return Bookmark(
                label: clipped,
                timestamp: item.timestamp,
                color: color,
                source: .ai
            )
        }
    }

    /// Extract a top-level JSON array from a possibly-fenced LLM response.
    /// Mirrors the structure of `extractJSON` but for `[...]` payloads.
    private static func extractJSONArray(from response: String) -> String? {
        var cleaned = response
        if let fenceStart = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
            if let fenceEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
        }
        guard let jsonStart = cleaned.firstIndex(of: "[") else { return nil }

        var depth = 0
        var jsonEnd = jsonStart
        var inString = false
        var prevChar: Character = " "

        for index in cleaned[jsonStart...].indices {
            let char = cleaned[index]
            if char == "\"", prevChar != "\\" {
                inString.toggle()
            }
            if !inString {
                if char == "[" {
                    depth += 1
                }
                if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = index
                        break
                    }
                }
            }
            prevChar = char
        }

        guard depth == 0 else { return nil }
        return String(cleaned[jsonStart ... jsonEnd])
    }

    /// Parse Smart Minutes JSON from LLM response.
    static func parseSmartMinutes(from response: String) -> SmartMinutes? {
        guard let jsonString = extractJSON(from: response) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }

        struct RawMinutes: Decodable {
            var summary: String?
            var keyDecisions: [String]?
            var discussionPoints: [String]?
            var actionItems: [RawActionItem]?
            var followUps: [String]?
            var attendeeSummary: [RawAttendee]?
        }

        struct RawActionItem: Decodable {
            var title: String
            var assignee: String?
            var due: String?
        }

        struct RawAttendee: Decodable {
            var name: String
            var keyPoints: [String]?
            var speakingTimePercent: Double?
        }

        let raw: RawMinutes
        do {
            raw = try JSONDecoder().decode(RawMinutes.self, from: data)
        } catch {
            let logger = Logger(subsystem: AppConstants.bundleID, category: "MeetingPromptBuilder")
            logger.warning("Smart Minutes JSON decode failed: \(error.localizedDescription, privacy: .public)")
            logger.debug("Raw JSON (truncated): \(jsonString.prefix(500), privacy: .private)")
            return nil
        }

        return SmartMinutes(
            keyDecisions: raw.keyDecisions ?? [],
            discussionPoints: raw.discussionPoints ?? [],
            actionItems: raw.actionItems?.map(\.title) ?? [],
            followUps: raw.followUps ?? [],
            attendeeSummary: raw.attendeeSummary?.map { attendee in
                AttendeeContribution(
                    name: attendee.name,
                    keyPoints: attendee.keyPoints ?? [],
                    speakingTimePercent: attendee.speakingTimePercent ?? 0
                )
            } ?? []
        )
    }

    /// Extract the summary text field from the LLM response JSON.
    static func parseSummaryText(from response: String) -> String? {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String
        else { return nil }
        return summary
    }

    /// Extract action items from the LLM response.
    static func parseActionItems(from response: String, relativeTo referenceDate: Date = .now) -> [ActionItem] {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8)
        else { return [] }

        struct RawResponse: Decodable {
            var actionItems: [RawItem]?
        }

        struct RawItem: Decodable {
            var title: String
            var assignee: String?
            var due: String?
        }

        guard let raw = try? JSONDecoder().decode(RawResponse.self, from: data),
              let items = raw.actionItems
        else { return [] }

        return items.map { item in
            let sanitizedDue = item.due.flatMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                return (trimmed.isEmpty || trimmed.lowercased() == "null" || trimmed.lowercased() == "n/a") ? nil : trimmed
            }
            let sanitizedAssignee = item.assignee.flatMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                return (trimmed.isEmpty || trimmed.lowercased() == "null" || trimmed.lowercased() == "n/a") ? nil : trimmed
            }
            let dueDate = sanitizedDue.flatMap { parseDueDate(from: $0, relativeTo: referenceDate) }
            return ActionItem(
                title: item.title,
                assignee: sanitizedAssignee,
                dueDescription: sanitizedDue,
                dueDate: dueDate
            )
        }
    }

    /// Extract topic keywords from the LLM response JSON.
    static func parseTopicKeywords(from response: String) -> [String] {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keywords = json["topicKeywords"] as? [String]
        else { return [] }
        return keywords
    }

    // MARK: - Due Date Parsing

    /// Parse a human-readable due description into an actual Date.
    /// Handles common patterns: "tomorrow", "next Monday", "end of week",
    /// "March 15", "2025-03-15", "in 3 days", "by Friday", etc.
    static func parseDueDate(from description: String, relativeTo reference: Date = .now) -> Date? {
        let lowered = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current

        return parseRelativeKeyword(lowered, calendar: calendar, reference: reference)
            ?? parseInNDuration(lowered, calendar: calendar, reference: reference)
            ?? parseWeekdayName(lowered, calendar: calendar, reference: reference)
            ?? parseFormattedDate(description, lowered: lowered, calendar: calendar, reference: reference)
    }

    private static func parseRelativeKeyword(_ lowered: String, calendar: Calendar, reference: Date) -> Date? {
        let todayKeywords: Set = ["today", "by today", "eod", "end of day"]
        if todayKeywords.contains(lowered) {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: reference)
        }

        let tomorrowKeywords: Set = ["tomorrow", "by tomorrow"]
        if tomorrowKeywords.contains(lowered) {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }

        let eowKeywords: Set = ["end of week", "eow", "this week", "by end of week"]
        if eowKeywords.contains(lowered) {
            let weekday = calendar.component(.weekday, from: reference)
            let daysUntilFriday = (6 - weekday + 7) % 7 // Friday = 6
            let friday = calendar.date(byAdding: .day, value: max(daysUntilFriday, 1), to: reference)
            return friday.flatMap { calendar.date(bySettingHour: 17, minute: 0, second: 0, of: $0) }
        }

        let nextWeekKeywords: Set = ["next week", "by next week"]
        if nextWeekKeywords.contains(lowered) {
            guard let nextMonday = calendar.date(byAdding: .weekOfYear, value: 1, to: reference) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonday)
        }

        return nil
    }

    private static func parseInNDuration(_ lowered: String, calendar: Calendar, reference: Date) -> Date? {
        guard let match = lowered.firstMatch(of: /in\s+(\d+)\s+(day|days|week|weeks)/),
              let count = Int(match.1)
        else { return nil }
        let component: Calendar.Component = String(match.2).hasPrefix("week") ? .weekOfYear : .day
        guard let date = calendar.date(byAdding: component, value: count, to: reference) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }

    private static func parseWeekdayName(_ lowered: String, calendar: Calendar, reference: Date) -> Date? {
        let weekdayNames: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
        ]
        for (name, targetWeekday) in weekdayNames where lowered.contains(name) {
            let currentWeekday = calendar.component(.weekday, from: reference)
            var daysAhead = targetWeekday - currentWeekday
            if daysAhead <= 0 {
                daysAhead += 7
            }
            if lowered.hasPrefix("next") {
                daysAhead += 7
            }
            guard let date = calendar.date(byAdding: .day, value: daysAhead, to: reference) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        }
        return nil
    }

    private static func parseFormattedDate(_ description: String, lowered: String, calendar: Calendar, reference: Date) -> Date? {
        // ISO date "YYYY-MM-DD"
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = isoFormatter.date(from: lowered) {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        }

        // Natural date "March 15" / "Mar 15" / "March 15, 2025"
        let naturalFormats = [
            "MMMM d, yyyy", "MMMM d yyyy", "MMMM d",
            "MMM d, yyyy", "MMM d yyyy", "MMM d",
            "M/d/yyyy", "M/d",
        ]
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in naturalFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if var date = formatter.date(from: trimmed) {
                if !format.contains("y") {
                    var components = calendar.dateComponents([.month, .day], from: date)
                    components.year = calendar.component(.year, from: reference)
                    if let adjusted = calendar.date(from: components), adjusted < reference {
                        components.year = calendar.component(.year, from: reference) + 1
                    }
                    date = calendar.date(from: components) ?? date
                }
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            }
        }

        return nil
    }
}
