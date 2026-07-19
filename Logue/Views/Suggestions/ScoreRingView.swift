import SwiftUI

/// Animated circular score indicator (0–100).
struct ScoreRingView: View {
    let score: Double
    let size: CGFloat

    private var ringColor: Color {
        if score >= 85 {
            return .green
        }
        if score >= 65 {
            return .orange
        }
        return .red
    }

    private var trackWidth: CGFloat {
        size * 0.10
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(ringColor.opacity(AppThemeConstants.opacityMedium), lineWidth: trackWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: score / 100)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: score)

            // Label
            VStack(spacing: 1) {
                Text("\(Int(score))")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(ringColor)
                    .animation(.spring(response: 0.6), value: score)
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score: \(Int(score)) out of 100")
        .accessibilityValue("\(Int(score))%")
    }
}

// MARK: - Category Score Bar

struct CategoryScoreBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(score))")
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
                        .frame(width: geo.size.width * (score / 100), height: 4)
                        .animation(.spring(response: 0.5), value: score)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(score)) out of 100")
        .accessibilityValue("\(Int(score))%")
    }
}
