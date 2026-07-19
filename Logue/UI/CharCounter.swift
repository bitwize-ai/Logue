import SwiftUI

/// Subtle char/token counter that appears only when the user is within
/// `warningThreshold` (default 80%) of the limit. Pulses red when over.
///
/// Visibility is intentional: showing "0 / 4000" all the time is noisy.
/// Showing it only when it matters keeps the input bar calm.
struct CharCounter: View {
    let count: Int
    let limit: Int
    var warningThreshold: Double = 0.8

    var body: some View {
        if shouldShow {
            HStack(spacing: 4) {
                Image(systemName: ratio >= 1.0 ? "exclamationmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(formatted(count)) / \(formatted(limit))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.08))
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .accessibilityLabel("\(count) of \(limit) characters used")
        }
    }

    private var ratio: Double {
        guard limit > 0 else { return 0 }
        return Double(count) / Double(limit)
    }

    private var shouldShow: Bool {
        ratio >= warningThreshold
    }

    private var tint: Color {
        if ratio >= 1.0 {
            return .red
        }
        if ratio >= 0.95 {
            return .orange
        }
        return .secondary
    }

    private func formatted(_ value: Int) -> String {
        if value >= 1000 {
            let truncated = Double(value) / 1000.0
            return String(format: "%.1fk", truncated)
        }
        return "\(value)"
    }
}
