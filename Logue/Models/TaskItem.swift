import Foundation

// MARK: - TaskStatus

/// Whether a task is still open.
enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo
    case done
}

// MARK: - TaskPriority

/// How urgent a task is.
///
/// `Comparable` so sorting is meaningful rather than alphabetical — `.high` sorting below
/// `.low` by raw value is exactly the bug this prevents.
enum TaskPriority: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var symbolName: String {
        switch self {
        case .low: "arrow.down"
        case .medium: "equal"
        case .high: "exclamationmark"
        }
    }
}

// MARK: - TaskRecurrence

/// How often a task repeats.
///
/// A unit and a bounded count rather than a free string, because an unparseable recurrence
/// would either never reopen the task or reopen it forever — and both failures are silent.
struct TaskRecurrence: Codable, Sendable, Equatable {
    enum Unit: String, Codable, Sendable, CaseIterable {
        case day
        case week
        case month
    }

    /// A year. Longer than this is indistinguishable from a typo.
    static let maxInterval = 365

    let unit: Unit
    let interval: Int

    /// Clamped on construction, so no other code has to defend against a zero interval.
    init(unit: Unit, interval: Int) {
        self.unit = unit
        self.interval = min(max(interval, 1), Self.maxInterval)
    }

    /// The next due date after `date`.
    ///
    /// `calendar` is a parameter rather than `.current` so the rule is deterministic: month
    /// arithmetic across a DST boundary is where a hidden current calendar produces a test
    /// that passes in one timezone and fails in another.
    func nextDueDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch unit {
        case .day: calendar.date(byAdding: .day, value: interval, to: date)
        case .week: calendar.date(byAdding: .day, value: interval * 7, to: date)
        case .month: calendar.date(byAdding: .month, value: interval, to: date)
        }
    }

    /// The frontmatter form — `1d`, `2w`, `6m`.
    var storageString: String {
        "\(interval)\(unit.rawValue.prefix(1))"
    }

    var displayName: String {
        interval == 1 ? "Every \(unit.rawValue)" : "Every \(interval) \(unit.rawValue)s"
    }

    /// Parses the storage form, plus the three words a person might write by hand.
    ///
    /// Returns `nil` rather than a default for anything else: guessing here means silently
    /// giving a task a repetition the user never asked for.
    static func parse(_ raw: String) -> TaskRecurrence? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "daily": return TaskRecurrence(unit: .day, interval: 1)
        case "weekly": return TaskRecurrence(unit: .week, interval: 1)
        case "monthly": return TaskRecurrence(unit: .month, interval: 1)
        default: break
        }

        guard let suffix = value.last,
              let unit = Unit.allCases.first(where: { $0.rawValue.hasPrefix(String(suffix)) }),
              let interval = Int(value.dropLast()), interval > 0
        else { return nil }
        return TaskRecurrence(unit: unit, interval: interval)
    }
}

// MARK: - TaskItem

/// A task the user owns.
///
/// Deliberately separate from `ActionItem`, which is what the model pulled out of one
/// meeting and lives inside that meeting. A `TaskItem` outlives its origin: it can be
/// created from nothing, promoted from an action item, repeat, and be filed in a space.
struct TaskItem: Identifiable, Codable, Sendable, Equatable {
    /// Titles are user-controlled and reach both filenames and LLM prompts.
    static let maxTitleLength = 200

    var id: UUID
    var title: String
    var status: TaskStatus
    var priority: TaskPriority
    /// Day precision, held at the start of its day so comparisons do not depend on what
    /// time of day the task happened to be made.
    var dueDate: Date?
    var tags: [String]
    var spaceID: UUID?
    var recurrence: TaskRecurrence?
    var createdAt: Date
    var updatedAt: Date
    /// How many times a repeating task has been completed.
    var completedCount: Int
    /// The meeting this was promoted from, so the task can link back to where it was decided.
    var sourceMeetingID: UUID?
    /// Free markdown below the frontmatter.
    var notes: String

    /// Written out rather than synthesized: declaring `init(from:)` below removes the
    /// memberwise initialiser, and every call site depends on the defaults.
    init(
        id: UUID = UUID(),
        title: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        tags: [String] = [],
        spaceID: UUID? = nil,
        recurrence: TaskRecurrence? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedCount: Int = 0,
        sourceMeetingID: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.tags = tags
        self.spaceID = spaceID
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedCount = completedCount
        self.sourceMeetingID = sourceMeetingID
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, dueDate, tags, spaceID
        case recurrence, createdAt, updatedAt, completedCount, sourceMeetingID, notes
    }

    /// Explicit because synthesized `Codable` throws `keyNotFound` for a missing
    /// non-optional key **even when the property has a default** — so a task written by an
    /// older build would fail to decode the moment a field is added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        completedCount = try container.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0
        sourceMeetingID = try container.decodeIfPresent(UUID.self, forKey: .sourceMeetingID)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    // MARK: - Derived

    var isOverdue: Bool {
        guard status == .todo, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}
