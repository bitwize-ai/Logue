import Foundation

/// Computes aggregate metrics from MeetingStore and DocumentStore for the Insights dashboard.
@Observable
@MainActor
final class InsightsStatsProvider {
    private let meetingStore: MeetingStore
    private let documentStore: DocumentStore

    init(meetingStore: MeetingStore, documentStore: DocumentStore) {
        self.meetingStore = meetingStore
        self.documentStore = documentStore
    }

    // MARK: - Data Types

    struct DayActivity: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let meetingCount: Int
        let documentCount: Int
        let isToday: Bool
    }

    struct ActionItemStats {
        let total: Int
        let completed: Int
        let pending: Int
        let overdue: Int
        let completionRate: Double
    }

    struct TimeTrend {
        let thisWeekSeconds: TimeInterval
        let lastWeekSeconds: TimeInterval
        let deltaPercent: Double
        let thisWeekFormatted: String
        let lastWeekFormatted: String
    }

    struct TemplateBreakdown: Identifiable {
        let id = UUID()
        let template: MeetingTemplate
        let count: Int
        let percentage: Double
    }

    struct DocStats {
        let totalDocuments: Int
        let totalWordCount: Int
        let avgReadability: Double
        let totalReadingMinutes: Int
        let avgCorrectness: Double
        let avgClarity: Double
    }

    struct MonthlyStats {
        let meetingCount: Int
        let totalSeconds: TimeInterval
        let totalFormatted: String
        let documentsCreated: Int
    }

    // MARK: - Computed Metrics

    private var activeMeetings: [MeetingNote] {
        meetingStore.meetings.filter { !$0.isArchived && !$0.isTrashed }
    }

    var hasData: Bool {
        !activeMeetings.isEmpty || !documentStore.activeDocuments.isEmpty
    }

    // MARK: - Cached Formatters

    private static let eeeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let eeeeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    // MARK: Weekly Activity (last 7 days)

    var weeklyActivity: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0 ..< 7).reversed().map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return DayActivity(date: today, dayLabel: "", meetingCount: 0, documentCount: 0, isToday: false)
            }
            let mCount = activeMeetings.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.count
            let dCount = documentStore.activeDocuments.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.count
            return DayActivity(
                date: date,
                dayLabel: Self.eeeFormatter.string(from: date),
                meetingCount: mCount,
                documentCount: dCount,
                isToday: daysAgo == 0
            )
        }
    }

    var busiestDayOfWeek: String? {
        let activity = weeklyActivity
        let busiest = activity.max(by: { $0.meetingCount < $1.meetingCount })
        guard let busiest, busiest.meetingCount > 0 else { return nil }
        return Self.eeeeFormatter.string(from: busiest.date)
    }

    // MARK: Action Items

    var actionItemStats: ActionItemStats {
        let allItems = activeMeetings.flatMap(\.actionItems)
        let total = allItems.count
        let completed = allItems.filter(\.isCompleted).count
        let pending = total - completed
        let overdue = allItems.filter { item in
            guard !item.isCompleted, let due = item.dueDate else { return false }
            return due < Date()
        }.count
        let rate = total > 0 ? Double(completed) / Double(total) * 100 : 0
        return ActionItemStats(total: total, completed: completed, pending: pending, overdue: overdue, completionRate: rate)
    }

    // MARK: Meeting Time Trend

    var meetingTimeTrend: TimeTrend {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfWeek) ?? today

        let thisWeek = activeMeetings
            .filter { $0.createdAt >= startOfWeek }
            .reduce(0.0) { $0 + $1.duration }

        let lastWeek = activeMeetings
            .filter { $0.createdAt >= startOfLastWeek && $0.createdAt < startOfWeek }
            .reduce(0.0) { $0 + $1.duration }

        let delta: Double = lastWeek > 0 ? ((thisWeek - lastWeek) / lastWeek) * 100 : (thisWeek > 0 ? 100 : 0)

        return TimeTrend(
            thisWeekSeconds: thisWeek,
            lastWeekSeconds: lastWeek,
            deltaPercent: delta,
            thisWeekFormatted: DurationFormatter.hoursMinutes(thisWeek),
            lastWeekFormatted: DurationFormatter.hoursMinutes(lastWeek)
        )
    }

    // MARK: Meeting Breakdown by Template

    var meetingBreakdown: [TemplateBreakdown] {
        let total = activeMeetings.count
        guard total > 0 else { return [] }

        var counts: [MeetingTemplate: Int] = [:]
        for meeting in activeMeetings {
            counts[meeting.template, default: 0] += 1
        }

        return counts
            .map { TemplateBreakdown(template: $0.key, count: $0.value, percentage: Double($0.value) / Double(total) * 100) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Monthly Stats

    var monthlyStats: MonthlyStats {
        let calendar = Calendar.current
        let now = Date()
        let monthMeetings = activeMeetings.filter {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }
        let totalTime = monthMeetings.reduce(0.0) { $0 + $1.duration }
        let monthDocs = documentStore.activeDocuments.filter {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }
        return MonthlyStats(
            meetingCount: monthMeetings.count,
            totalSeconds: totalTime,
            totalFormatted: DurationFormatter.hoursMinutes(totalTime),
            documentsCreated: monthDocs.count
        )
    }

    // MARK: Document Stats

    var documentStats: DocStats {
        let docs = documentStore.activeDocuments
        let totalWords = docs.reduce(0) { $0 + $1.wordCount }
        let totalReading = Int(ceil(docs.reduce(0.0) { $0 + $1.readingTimeMinutes }))
        let scored = docs.compactMap(\.score)
        let avgScore = scored.isEmpty ? 0 : scored.reduce(0.0) { $0 + $1.overall } / Double(scored.count)
        let avgCorrectness = scored.isEmpty ? 0 : scored.reduce(0.0) { $0 + $1.correctness } / Double(scored.count)
        let avgClarity = scored.isEmpty ? 0 : scored.reduce(0.0) { $0 + $1.clarity } / Double(scored.count)
        return DocStats(
            totalDocuments: docs.count,
            totalWordCount: totalWords,
            avgReadability: avgScore,
            totalReadingMinutes: totalReading,
            avgCorrectness: avgCorrectness,
            avgClarity: avgClarity
        )
    }
}
