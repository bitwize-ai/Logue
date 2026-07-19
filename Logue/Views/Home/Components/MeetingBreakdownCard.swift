import SwiftUI

/// Horizontal bar breakdown of meetings by template type.
struct MeetingBreakdownCard: View {
    let breakdown: [InsightsStatsProvider.TemplateBreakdown]

    private static let templateColors: [MeetingTemplate: Color] = [
        .general: AppThemeConstants.accent,
        .oneOnOne: AppThemeConstants.categoryPurple,
        .standup: AppThemeConstants.warning,
        .interview: .cyan,
        .brainstorm: AppThemeConstants.pinnedColor,
        .presentation: AppThemeConstants.success,
    ]

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(icon: "chart.bar.doc.horizontal", title: "Meeting Types")

                if breakdown.isEmpty {
                    Text("No meetings recorded yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(breakdown) { item in
                            breakdownRow(item)
                        }
                    }
                }
            }
        }
    }

    private func breakdownRow(_ item: InsightsStatsProvider.TemplateBreakdown) -> some View {
        let color = Self.templateColors[item.template] ?? AppThemeConstants.categoryGray

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: item.template.iconName)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(item.template.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(item.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(AppThemeConstants.activeOpacity))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * (item.percentage / 100), height: 4)
                        .animation(.spring(response: 0.5), value: item.percentage)
                }
            }
            .frame(height: 4)
        }
    }
}
