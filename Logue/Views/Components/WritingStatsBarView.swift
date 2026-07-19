import SwiftUI

/// Bottom status bar showing live word count, reading time, readability score, and analysis state.
struct WritingStatsBarView: View {
    let text: String
    let isAnalyzing: Bool
    let errorMessage: String?

    private var stats: WritingStats {
        WritingStats.compute(from: text)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppThemeConstants.error)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
            } else {
                statsRow
            }
        }
        .frame(height: 26)
        .background(AppThemeConstants.chromeBackground)
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            if isAnalyzing {
                Label("Analysing…", systemImage: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statItem(label: "Words", value: "\(stats.wordCount)")
            statItem(label: "Sentences", value: "\(stats.sentenceCount)")
            statItem(label: "Readability", value: String(format: "%.0f", stats.fleschReadingEase))

            Spacer()

            // Reading time
            let minutes = Double(stats.wordCount) / 238.0
            if minutes >= 1 {
                Text("\(Int(ceil(minutes))) min read")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
    }

    private func statItem(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
