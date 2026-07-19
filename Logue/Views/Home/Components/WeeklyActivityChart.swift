import Charts
import SwiftUI

/// Stacked bar chart showing meetings & documents per day for the last 7 days.
struct WeeklyActivityChart: View {
    let activity: [InsightsStatsProvider.DayActivity]
    let busiestDay: String?

    private static let meetingColor = AppThemeConstants.accent
    private static let documentColor = AppThemeConstants.categoryPurple

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(icon: "chart.bar.xaxis", title: "Weekly Activity")

                Chart(activity) { day in
                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Count", day.meetingCount)
                    )
                    .foregroundStyle(day.isToday ? Self.meetingColor : Self.meetingColor.opacity(AppThemeConstants.opacityMuted))
                    .cornerRadius(AppThemeConstants.radiusXSmall)
                    .position(by: .value("Type", "Meetings"))

                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Count", day.documentCount)
                    )
                    .foregroundStyle(day.isToday ? Self.documentColor : Self.documentColor.opacity(AppThemeConstants.opacityMuted))
                    .cornerRadius(AppThemeConstants.radiusXSmall)
                    .position(by: .value("Type", "Documents"))
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(.quaternary)
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 140)
                .accessibilityLabel("Weekly activity chart")
                .accessibilityValue(
                    "\(activity.reduce(0) { $0 + $1.meetingCount }) meetings and \(activity.reduce(0) { $0 + $1.documentCount }) documents this week"
                )

                // Legend + busiest day
                HStack(spacing: 16) {
                    legendItem(color: Self.meetingColor, label: "Meetings")
                    legendItem(color: Self.documentColor, label: "Documents")
                    Spacer()
                    if let busiestDay {
                        Text("Busiest: \(busiestDay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
