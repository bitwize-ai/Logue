import SwiftUI

/// Floating "Stop generating" pill shown above the input bar while a
/// response is streaming. Tap (or `Esc`) cancels the in-flight request.
///
/// Mirrors ChatGPT / Claude desktop pattern. The actual cancel logic
/// lives in `AgentCoordinator`; this view just exposes the affordance.
struct StopGeneratingPill: View {
    var onStop: () -> Void

    var body: some View {
        Button {
            HapticFeedback.stop()
            onStop()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Stop generating")
                    .font(.system(size: 11, weight: .medium))
                Text("⎋")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(.regularMaterial)
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Stop generating response")
    }
}
