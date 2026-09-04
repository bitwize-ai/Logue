import SwiftUI

/// A mode that is on for the next send, with a way to turn it off.
///
/// Lifted out of `InputBarView` so the Command Center island shows the same chip rather than
/// drawing its own. Each surface owns its own one-shot keys and hands the value to the
/// coordinator at send time, so this is the only thing keeping the two from describing the
/// same mode in two voices — which is why the titles come from `UICopy` rather than being
/// typed at each call site.
struct ModeChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// Turns the mode off. The `×` exists so a mode can be dropped without reopening the menu
    /// that set it.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Turn off \(title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.5))
        // A scale is a transition, not a pulse — so it follows `entrance`.
        .transition(
            IslandMotion.entrance(reduceMotion: reduceMotion) == .slideAndFade
                ? .scale.combined(with: .opacity)
                : .opacity
        )
    }
}
