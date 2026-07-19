import SwiftUI

/// Single-line contextual summary replacing the hero stats row.
/// Shows today's meetings, overdue action items, and recent document activity as tappable pills.
struct HomeContextBar: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(InsightsStatsProvider.self) private var insights

    var body: some View {
        let todayCount = todaysMeetingCount
        let overdueCount = insights.actionItemStats.overdue
        let pendingCount = insights.actionItemStats.pending
        let recentDocCount = recentDocumentCount

        HStack(spacing: 0) {
            if todayCount > 0 {
                pill(
                    icon: "waveform",
                    text: "\(todayCount) meeting\(todayCount == 1 ? "" : "s") today",
                    color: AppThemeConstants.accent
                )
            }

            if overdueCount > 0 {
                if todayCount > 0 {
                    separator
                }
                pill(
                    icon: "exclamationmark.circle.fill",
                    text: "\(overdueCount) overdue",
                    color: AppThemeConstants.error
                )
            } else if pendingCount > 0 {
                if todayCount > 0 {
                    separator
                }
                pill(
                    icon: "checklist",
                    text: "\(pendingCount) pending",
                    color: AppThemeConstants.warning
                )
            }

            if recentDocCount > 0 {
                if todayCount > 0 || overdueCount > 0 || pendingCount > 0 {
                    separator
                }
                pill(
                    icon: "doc.text",
                    text: "\(recentDocCount) doc\(recentDocCount == 1 ? "" : "s") this week",
                    color: AppThemeConstants.categoryPurple
                )
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Pill

    private func pill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var separator: some View {
        Text("·")
            .font(.caption)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 8)
    }

    // MARK: - Data

    private var todaysMeetingCount: Int {
        let cal = Calendar.current
        return meetingStore.activeMeetings
            .filter { cal.isDateInToday($0.createdAt) && !$0.isArchived }
            .count
    }

    private var recentDocumentCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return documentStore.activeDocuments
            .filter { $0.modifiedAt >= weekAgo }
            .count
    }
}
