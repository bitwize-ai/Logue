import SwiftUI

/// A subtle pulsing dot used to signal live background activity (agent streaming, etc).
struct PulsingDot: View {
    var color: Color = AppThemeConstants.brandPrimary
    var size: CGFloat = 8

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0.7

    /// Honoured here rather than at each call site, so a dot added somewhere new cannot
    /// reintroduce a forever-repeating animation for someone who asked for less movement.
    /// Safe to stop entirely because every row this dot appears in also says, in words, what
    /// is happening — see `IslandMotion`.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear { applyPulse() }
            // Also on change, not only on appear. The dot outlives the setting: someone who
            // turns Reduce Motion on while the island is streaming would otherwise keep the
            // forever-repeating animation until the view was rebuilt, which is the one case
            // where they are most likely to be looking at it.
            .onChange(of: reduceMotion) { _, _ in applyPulse() }
            .accessibilityHidden(true)
    }

    private func applyPulse() {
        guard IslandMotion.allowsPulse(reduceMotion: reduceMotion) else {
            // Still visible, just still. Reset the scale too — turning the setting on
            // mid-pulse would otherwise freeze the dot at whatever size it had reached.
            withAnimation(.default) {
                scale = 1
                opacity = 1
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            scale = 1.25
            opacity = 1.0
        }
    }
}
