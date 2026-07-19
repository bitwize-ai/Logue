import Foundation

/// Represents a single recorded meeting with its transcript, summary, and action items.
struct MeetingNote: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    var duration: TimeInterval
    var segments: [TranscriptSegment]
    var actionItems: [ActionItem]
    var summary: String?
    var smartMinutes: SmartMinutes?
    var recordingMode: RecordingMode
    var isPinned: Bool
    var isArchived: Bool
    var tags: [String]
    var template: MeetingTemplate
    var bookmarks: [Bookmark]
    var transcriptionLanguage: String?
    var topicKeywords: [String]
    var calendarEventID: String?
    var scheduledStartTime: Date?
    var hasSpeakerData: Bool
    var speakers: [Speaker]
    var speakerSegments: [SpeakerSegment]
    /// Space this meeting belongs to; nil = unfiled.
    var spaceID: UUID?
    /// Document ID where the summary was saved; nil = not yet saved.
    var summaryDocumentID: UUID?
    /// AI chat conversation history for this meeting.
    var chatMessages: [MeetingChatMessage]
    /// Whether this meeting is in the trash.
    var isTrashed: Bool
    /// When the meeting was moved to trash.
    var trashedAt: Date?
    /// Local URL of the recorded audio file; nil if not yet recorded or file was cleared.
    var audioFileURL: URL?

    init(
        id: UUID = .init(),
        title: String = "Untitled Meeting",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        duration: TimeInterval = 0,
        segments: [TranscriptSegment] = [],
        actionItems: [ActionItem] = [],
        summary: String? = nil,
        smartMinutes: SmartMinutes? = nil,
        recordingMode: RecordingMode = .inPerson,
        isPinned: Bool = false,
        isArchived: Bool = false,
        tags: [String] = [],
        template: MeetingTemplate = .general,
        bookmarks: [Bookmark] = [],
        transcriptionLanguage: String? = nil,
        topicKeywords: [String] = [],
        calendarEventID: String? = nil,
        scheduledStartTime: Date? = nil,
        hasSpeakerData: Bool = false,
        speakers: [Speaker] = [],
        speakerSegments: [SpeakerSegment] = [],
        spaceID: UUID? = nil,
        summaryDocumentID: UUID? = nil,
        chatMessages: [MeetingChatMessage] = [],
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        audioFileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.duration = duration
        self.segments = segments
        self.actionItems = actionItems
        self.summary = summary
        self.smartMinutes = smartMinutes
        self.recordingMode = recordingMode
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.tags = tags
        self.template = template
        self.bookmarks = bookmarks
        self.transcriptionLanguage = transcriptionLanguage
        self.topicKeywords = topicKeywords
        self.calendarEventID = calendarEventID
        self.scheduledStartTime = scheduledStartTime
        self.hasSpeakerData = hasSpeakerData
        self.speakers = speakers
        self.speakerSegments = speakerSegments
        self.spaceID = spaceID
        self.summaryDocumentID = summaryDocumentID
        self.chatMessages = chatMessages
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.audioFileURL = audioFileURL
    }

    // MARK: - Codable (backwards-compatible)

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, duration, segments, actionItems
        case summary, smartMinutes, recordingMode
        case isPinned = "isFavorited"
        case isArchived, tags, template
        case bookmarks, transcriptionLanguage, topicKeywords
        case calendarEventID, scheduledStartTime
        case hasSpeakerData, speakers, speakerSegments
        case spaceID, summaryDocumentID, chatMessages
        case isTrashed, trashedAt
        case audioFileURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        smartMinutes = try container.decodeIfPresent(SmartMinutes.self, forKey: .smartMinutes)
        recordingMode = try container.decode(RecordingMode.self, forKey: .recordingMode)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        tags = try container.decode([String].self, forKey: .tags)
        template = try container.decodeIfPresent(MeetingTemplate.self, forKey: .template) ?? .general
        bookmarks = try container.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage)
        topicKeywords = try container.decodeIfPresent([String].self, forKey: .topicKeywords) ?? []
        calendarEventID = try container.decodeIfPresent(String.self, forKey: .calendarEventID)
        scheduledStartTime = try container.decodeIfPresent(Date.self, forKey: .scheduledStartTime)
        hasSpeakerData = try container.decodeIfPresent(Bool.self, forKey: .hasSpeakerData) ?? false
        speakers = try container.decodeIfPresent([Speaker].self, forKey: .speakers) ?? []
        speakerSegments = try container.decodeIfPresent([SpeakerSegment].self, forKey: .speakerSegments) ?? []
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        summaryDocumentID = try container.decodeIfPresent(UUID.self, forKey: .summaryDocumentID)
        chatMessages = try container.decodeIfPresent([MeetingChatMessage].self, forKey: .chatMessages) ?? []
        isTrashed = try container.decodeIfPresent(Bool.self, forKey: .isTrashed) ?? false
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        audioFileURL = try container.decodeIfPresent(URL.self, forKey: .audioFileURL)
    }

    // MARK: - Computed

    var fullTranscript: String {
        segments.map { segment in
            let speaker = segment.speakerLabel ?? "Speaker"
            return "[\(segment.formattedStartTime)] \(speaker): \(segment.text)"
        }.joined(separator: "\n")
    }

    var speakerNames: [String] {
        let names = Set(segments.compactMap(\.speakerLabel))
        return names.sorted()
    }

    var formattedDuration: String {
        TranscriptSegment.formatTime(duration)
    }
}

// MARK: - Meeting Template

enum MeetingTemplate: String, Codable, CaseIterable, Identifiable {
    case general = "General"
    case oneOnOne = "1-on-1"
    case standup = "Daily Standup"
    case interview = "Interview"
    case brainstorm = "Brainstorm"
    case presentation = "Presentation"

    var id: String {
        rawValue
    }

    var label: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .general: "doc.text"
        case .oneOnOne: "person.2"
        case .standup: "person.3"
        case .interview: "questionmark.bubble"
        case .brainstorm: "lightbulb"
        case .presentation: "play.rectangle"
        }
    }

    var description: String {
        switch self {
        case .general: "General-purpose meeting notes"
        case .oneOnOne: "Feedback, goals, and follow-ups"
        case .standup: "Yesterday, today, and blockers per person"
        case .interview: "Candidate assessment and recommendation"
        case .brainstorm: "Ideas, themes, and next steps"
        case .presentation: "Key takeaways and audience questions"
        }
    }
}

// MARK: - Recording Mode

enum RecordingMode: String, Codable, CaseIterable {
    case inPerson
    case onlineMeeting
    case voiceNote

    var label: String {
        switch self {
        case .inPerson: "In-Person (Mic)"
        case .onlineMeeting: "Online Meeting (System Audio)"
        case .voiceNote: "Voice Note"
        }
    }

    var iconName: String {
        switch self {
        case .inPerson: "mic.fill"
        case .onlineMeeting: "display"
        case .voiceNote: "mic.badge.plus"
        }
    }

    /// Recording modes shown in the "New Meeting" picker (excludes voice notes).
    static var meetingModes: [RecordingMode] {
        [.inPerson, .onlineMeeting]
    }

    var isVoiceNote: Bool {
        self == .voiceNote
    }
}

// MARK: - Smart Minutes

/// Structured meeting summary generated by the LLM — avoids "wall of text" problem.
struct SmartMinutes: Codable {
    var keyDecisions: [String]
    var discussionPoints: [String]
    var actionItems: [String]
    var followUps: [String]
    var attendeeSummary: [AttendeeContribution]
}

/// Summary of a single attendee's contributions during the meeting.
struct AttendeeContribution: Codable, Identifiable {
    var id: String {
        name
    }

    var name: String
    var keyPoints: [String]
    var speakingTimePercent: Double
}

// MARK: - Daily Digest

/// AI-generated daily summary across all meetings recorded today.
struct DailyDigest: Codable {
    var headline: String
    var totalMeetingTime: String
    var keyHighlights: [String]
    var pendingActions: [String]
    var tomorrowFocus: String?
}

// MARK: - Bookmark

/// A marker at a specific moment during recording — either placed by the user or
/// extracted by the post-recording AI pipeline as a "Smart Highlight".
struct Bookmark: Identifiable, Codable {
    let id: UUID
    var label: String
    let timestamp: TimeInterval
    let createdAt: Date
    var color: BookmarkColor
    /// Where this bookmark came from — user action vs. AI highlight extraction.
    /// Defaults to `.manual` for backwards compatibility with existing data.
    var source: Source

    enum Source: String, Codable {
        case manual
        case ai
    }

    init(
        id: UUID = .init(),
        label: String = "",
        timestamp: TimeInterval,
        createdAt: Date = .now,
        color: BookmarkColor = .orange,
        source: Source = .manual
    ) {
        self.id = id
        self.label = label
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.color = color
        self.source = source
    }

    var formattedTimestamp: String {
        TranscriptSegment.formatTime(timestamp)
    }

    // MARK: - Codable (backwards-compatible)

    enum CodingKeys: String, CodingKey {
        case id, label, timestamp, createdAt, color, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        color = try container.decode(BookmarkColor.self, forKey: .color)
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .manual
    }
}

enum BookmarkColor: String, Codable, CaseIterable {
    case red, orange, yellow, blue, purple

    var displayColor: String {
        switch self {
        case .red: "red"
        case .orange: "orange"
        case .yellow: "yellow"
        case .blue: "blue"
        case .purple: "purple"
        }
    }
}

// MARK: - Transcription Language

/// Common transcription languages supported by Apple's SpeechTranscriber.
enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"
    case russian = "ru"
    case turkish = "tr"
    case polish = "pl"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .auto: "Auto-detect"
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        case .korean: "Korean"
        case .arabic: "Arabic"
        case .hindi: "Hindi"
        case .russian: "Russian"
        case .turkish: "Turkish"
        case .polish: "Polish"
        }
    }

    /// Returns the Locale for SpeechTranscriber, or nil for auto-detect (uses system default).
    var locale: Locale? {
        switch self {
        case .auto: nil
        case .english: Locale(identifier: "en-US")
        case .spanish: Locale(identifier: "es-ES")
        case .french: Locale(identifier: "fr-FR")
        case .german: Locale(identifier: "de-DE")
        case .italian: Locale(identifier: "it-IT")
        case .portuguese: Locale(identifier: "pt-BR")
        case .dutch: Locale(identifier: "nl-NL")
        case .japanese: Locale(identifier: "ja-JP")
        case .chinese: Locale(identifier: "zh-CN")
        case .korean: Locale(identifier: "ko-KR")
        case .arabic: Locale(identifier: "ar-SA")
        case .hindi: Locale(identifier: "hi-IN")
        case .russian: Locale(identifier: "ru-RU")
        case .turkish: Locale(identifier: "tr-TR")
        case .polish: Locale(identifier: "pl-PL")
        }
    }
}

// MARK: - Markdown Export

extension MeetingNote {
    /// Builds a Markdown representation of this meeting's Smart Minutes.
    func smartMinutesMarkdown() -> String {
        var content = "# \(title)\n\n"
        content += "**Date:** \(createdAt.formatted())  \n"
        content += "**Duration:** \(formattedDuration)\n\n"

        if let summary, !summary.isEmpty {
            content += summary + "\n\n"
        }

        if let minutes = smartMinutes {
            content += minutes.toMarkdown()
        } else if let summary {
            content += summary + "\n"
        }

        if !topicKeywords.isEmpty {
            content += "## Topics\n\n"
            content += topicKeywords.joined(separator: ", ") + "\n"
        }

        return content
    }
}

extension SmartMinutes {
    /// Formats the structured minutes as Markdown sections.
    func toMarkdown() -> String {
        var content = ""
        content += markdownSection("Key Decisions", items: keyDecisions)
        content += markdownSection("Discussion Points", items: discussionPoints)
        content += markdownChecklistSection("Action Items", items: actionItems)
        content += markdownSection("Follow-ups", items: followUps)
        content += attendeeMarkdown()
        return content
    }

    private func markdownSection(_ title: String, items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        var content = "## \(title)\n\n"
        for item in items {
            content += "- \(item)\n"
        }
        return content + "\n"
    }

    private func markdownChecklistSection(_ title: String, items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        var content = "## \(title)\n\n"
        for item in items {
            content += "- [ ] \(item)\n"
        }
        return content + "\n"
    }

    private func attendeeMarkdown() -> String {
        guard !attendeeSummary.isEmpty else { return "" }
        var content = "## Attendees\n\n"
        for attendee in attendeeSummary {
            content += "### \(attendee.name)"
            if attendee.speakingTimePercent > 0 {
                content += " (\(Int(attendee.speakingTimePercent))%)"
            }
            content += "\n\n"
            for point in attendee.keyPoints {
                content += "- \(point)\n"
            }
            content += "\n"
        }
        return content
    }
}
