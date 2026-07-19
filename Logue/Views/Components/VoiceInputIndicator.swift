import SwiftUI

/// Compact inline indicator shown while push-to-talk voice input is recording.
/// Displays a pulsing red dot, partial transcript, audio level, and stop button.
struct VoiceInputIndicator: View {
    let audioLevel: Float
    let partialTranscript: String
    let onStop: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppThemeConstants.error)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }

            Text(partialTranscript.isEmpty ? "Listening..." : partialTranscript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            AudioLevelBars(level: audioLevel)
                .frame(width: 36, height: 14)
                .accessibilityLabel("Audio level")
                .accessibilityValue("\(Int(min(max(Double(audioLevel), 0), 1) * 100)) percent")

            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.body)
                    .foregroundColor(AppThemeConstants.error)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(AppThemeConstants.error.opacity(AppThemeConstants.opacityLight))
                .overlay(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                        .strokeBorder(AppThemeConstants.error.opacity(AppThemeConstants.opacityMedium), lineWidth: 1)
                )
        )
    }
}

// MARK: - Audio Level Bars

private struct AudioLevelBars: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalized = min(max(CGFloat(level), 0), 1)
        let threshold = CGFloat(index) / CGFloat(barCount)
        return normalized > threshold ? 4 + normalized * 10 : 4
    }

    private func barColor(for index: Int) -> Color {
        let normalized = min(max(CGFloat(level), 0), 1)
        let threshold = CGFloat(index) / CGFloat(barCount)
        return normalized > threshold ? AppThemeConstants.error.opacity(0.7) : AppThemeConstants.error.opacity(0.2)
    }
}
