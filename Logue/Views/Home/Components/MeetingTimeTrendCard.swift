import SwiftUI

/// Shows total meeting time this week vs last week with a delta indicator.
struct MeetingTimeTrendCard: View {
    let trend: InsightsStatsProvider.TimeTrend

    private var isUp: Bool {
        trend.deltaPercent >= 0
    }

    private var deltaColor: Color {
        if trend.deltaPercent == 0 {
            return .secondary
        }
        return isUp ? AppThemeConstants.success : AppThemeConstants.warning
    }

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: "Meeting Time"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(trend.thisWeekFormatted)
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        if trend.lastWeekSeconds > 0 || trend.thisWeekSeconds > 0 {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(deltaColor)

                            Text("\(abs(Int(trend.deltaPercent)))%")
                                .font(.callout.weight(.medium).monospacedDigit())
                                .foregroundStyle(deltaColor)
                        }

                        Text("vs \(trend.lastWeekFormatted) last week")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
