import Foundation

/// A user-configurable automated AI task that runs on a schedule.
struct ScheduledTask: Identifiable, Codable {
    let id: UUID
    var taskType: TaskType
    var isEnabled: Bool
    var lastRunAt: Date?

    // MARK: - Schedule Configuration

    /// Hour of day (0–23) for time-based tasks (dailyDigest, autoSummarize, weeklyReview).
    var hour: Int
    /// Minute of hour (0–59).
    var minute: Int
    /// Day of week (1 = Sunday … 7 = Saturday) for weekly tasks.
    var dayOfWeek: Int?
    /// Minutes before a calendar event to trigger meeting prep.
    var minutesBefore: Int?

    // MARK: - Task Types

    enum TaskType: String, Codable, CaseIterable {
        case dailyDigest
        case meetingPrep
        case autoSummarize
        case weeklyReview

        var displayName: String {
            switch self {
            case .dailyDigest: "Daily Digest"
            case .meetingPrep: "Meeting Prep Briefing"
            case .autoSummarize: "Auto-Summarize Meetings"
            case .weeklyReview: "Weekly Action Item Review"
            }
        }

        var icon: String {
            switch self {
            case .dailyDigest: "sun.max.fill"
            case .meetingPrep: "calendar.badge.clock"
            case .autoSummarize: "sparkles"
            case .weeklyReview: "checklist"
            }
        }

        var description: String {
            switch self {
            case .dailyDigest:
                "Generate a summary digest of all today's meetings at a scheduled time."
            case .meetingPrep:
                "Generate a briefing with past context before upcoming calendar meetings."
            case .autoSummarize:
                "Automatically summarize meetings that don't have summaries yet."
            case .weeklyReview:
                "Compile all pending action items into a weekly review."
            }
        }

        /// Default schedule configuration for each task type.
        var defaultHour: Int {
            switch self {
            case .dailyDigest: 17 // 5 PM
            case .meetingPrep: 0 // Not time-based
            case .autoSummarize: 18 // 6 PM
            case .weeklyReview: 9 // 9 AM
            }
        }

        var defaultMinute: Int {
            0
        }

        /// Whether this task type uses a time-of-day schedule.
        var isTimeBased: Bool {
            self != .meetingPrep
        }

        /// Whether this task type can be triggered manually via a "Run Now" button.
        /// Meeting prep is event-triggered (fires before calendar events), not user-triggered.
        var supportsManualRun: Bool {
            self != .meetingPrep
        }
    }

    // MARK: - Factory

    static func defaultTask(for type: TaskType) -> ScheduledTask {
        ScheduledTask(
            id: UUID(),
            taskType: type,
            isEnabled: false,
            lastRunAt: nil,
            hour: type.defaultHour,
            minute: type.defaultMinute,
            dayOfWeek: type == .weeklyReview ? 2 : nil, // Monday
            minutesBefore: type == .meetingPrep ? 15 : nil
        )
    }
}

// MARK: - Task Run Record

/// Persisted record of a single scheduled task execution and its result.
struct TaskRunRecord: Identifiable, Codable {
    let id: UUID
    let taskType: ScheduledTask.TaskType
    let runAt: Date
    var status: Status
    var resultSummary: String
    /// When the task produced a document (e.g. weekly review), this links back to it
    /// so the run-history UI can offer an "Open Document" affordance.
    var createdDocumentID: UUID?

    enum Status: String, Codable {
        case success
        case noContent
        case failed
    }

    init(
        taskType: ScheduledTask.TaskType,
        runAt: Date = .now,
        status: Status,
        resultSummary: String,
        createdDocumentID: UUID? = nil
    ) {
        id = UUID()
        self.taskType = taskType
        self.runAt = runAt
        self.status = status
        self.resultSummary = resultSummary
        self.createdDocumentID = createdDocumentID
    }

    // MARK: - Codable (backwards-compatible)

    enum CodingKeys: String, CodingKey {
        case id, taskType, runAt, status, resultSummary, createdDocumentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskType = try container.decode(ScheduledTask.TaskType.self, forKey: .taskType)
        runAt = try container.decode(Date.self, forKey: .runAt)
        status = try container.decode(Status.self, forKey: .status)
        resultSummary = try container.decode(String.self, forKey: .resultSummary)
        createdDocumentID = try container.decodeIfPresent(UUID.self, forKey: .createdDocumentID)
    }
}
