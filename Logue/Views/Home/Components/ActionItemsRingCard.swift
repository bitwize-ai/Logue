import SwiftUI

/// Circular ring showing action item completion rate.
struct ActionItemsRingCard: View {
    let stats: InsightsStatsProvider.ActionItemStats

    private var ringColor: Color {
        if stats.completionRate >= 80 {
            return AppThemeConstants.success
        }
        if stats.completionRate >= 50 {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.error
    }

    private var trackWidth: CGFloat {
        6
    }

    private let ringSize: CGFloat = 64

    var body: some View {
        InsightCardShell {
            VStack(spacing: 10) {
                CardSectionHeader(icon: "checkmark.circle", title: "Action Items")

                HStack(spacing: 14) {
                    // Ring
                    ZStack {
                        Circle()
                            .stroke(ringColor.opacity(AppThemeConstants.opacityMedium), lineWidth: trackWidth)

                        Circle()
                            .trim(from: 0, to: stats.total > 0 ? stats.completionRate / 100 : 0)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: stats.completionRate)

                        VStack(spacing: 0) {
                            Text("\(stats.completed)")
                                .font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(ringColor)
                            Text("/\(stats.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: ringSize, height: ringSize)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(stats.completed) of \(stats.total) action items completed")

                    // Labels
                    VStack(alignment: .leading, spacing: 6) {
                        statLabel(value: "\(stats.pending)", label: "Pending", color: .secondary)
                        if stats.overdue > 0 {
                            statLabel(value: "\(stats.overdue)", label: "Overdue", color: AppThemeConstants.error)
                        }
                        statLabel(
                            value: "\(Int(stats.completionRate))%",
                            label: "Complete",
                            color: ringColor
                        )
                    }

                    Spacer()
                }
            }
        }
    }

    private func statLabel(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
