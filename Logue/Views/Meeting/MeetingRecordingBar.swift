import SwiftUI

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    let level: Float
    private let barCount = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< barCount, id: \.self) { index in
                AudioLevelBar(
                    index: index,
                    barCount: barCount,
                    level: level
                )
            }
        }
        .accessibilityLabel("Audio level meter")
        .accessibilityValue("\(Int(min(level, 1.0) * 100)) percent")
    }
}

private struct AudioLevelBar: View {
    let index: Int
    let barCount: Int
    let level: Float

    var body: some View {
        let threshold = Float(index) / Float(barCount)
        let normalizedLevel = min(level, 1.0)
        let active = normalizedLevel > threshold
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor(active: active))
            .frame(maxWidth: 5, maxHeight: .infinity)
    }

    private func barColor(active: Bool) -> Color {
        guard active else { return AppThemeConstants.categoryGray.opacity(0.2) }
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.5 {
            return AppThemeConstants.success
        }
        if ratio < 0.75 {
            return AppThemeConstants.categoryYellow
        }
        return AppThemeConstants.error
    }
}
