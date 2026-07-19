import SwiftUI

/// Insights dashboard section for the Overview page — charts and stats cards.
struct InsightsSectionView: View {
    @Environment(InsightsStatsProvider.self) private var insights

    var body: some View {
        if insights.hasData {
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(icon: "chart.bar.xaxis", title: "Insights")
                    .padding(.horizontal, 24)

                // Weekly Activity (left) + Action Items + Document Stats stacked (right)
                HStack(alignment: .top, spacing: 12) {
                    WeeklyActivityChart(
                        activity: insights.weeklyActivity,
                        busiestDay: insights.busiestDayOfWeek
                    )
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 12) {
                        ActionItemsRingCard(stats: insights.actionItemStats)
                        DocumentStatsCard(stats: insights.documentStats)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
