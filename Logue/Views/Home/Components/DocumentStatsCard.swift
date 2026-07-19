import SwiftUI

/// Aggregate document statistics: words, reading time, score breakdown.
struct DocumentStatsCard: View {
    let stats: InsightsStatsProvider.DocStats

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 6) {
                CardSectionHeader(icon: "doc.text.magnifyingglass", title: "Documents")

                // Row 1: Words + Reading Time
                HStack(spacing: 12) {
                    inlineStat(icon: "text.word.spacing", value: formattedWordCount, label: "Words", color: AppThemeConstants.accent)
                    Divider().frame(height: 16)
                    inlineStat(icon: "clock", value: formattedReadingTime, label: "Read Time", color: AppThemeConstants.success)
                    Spacer()
                }

                // Row 2: Score breakdown
                HStack(spacing: 12) {
                    inlineStat(icon: "star", value: scoreValue(stats.avgReadability), label: "Score", color: AppThemeConstants.warning)
                    Divider().frame(height: 16)
                    inlineStat(icon: "checkmark.seal", value: scoreValue(stats.avgCorrectness), label: "Correct", color: AppThemeConstants.success)
                    Divider().frame(height: 16)
                    inlineStat(icon: "eye", value: scoreValue(stats.avgClarity), label: "Clarity", color: .cyan)
                    Spacer()
                }
            }
        }
    }

    private func inlineStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scoreValue(_ value: Double) -> String {
        value > 0 ? "\(Int(value))" : "—"
    }

    private var formattedWordCount: String {
        if stats.totalWordCount >= 1000 {
            let k = Double(stats.totalWordCount) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(stats.totalWordCount)"
    }

    private var formattedReadingTime: String {
        let mins = stats.totalReadingMinutes
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }
}
