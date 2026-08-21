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
            .onAppear {
                guard IslandMotion.allowsPulse(reduceMotion: reduceMotion) else {
                    // Still visible, just still.
                    opacity = 1
                    return
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    scale = 1.25
                    opacity = 1.0
                }
            }
            .accessibilityHidden(true)
    }
}
