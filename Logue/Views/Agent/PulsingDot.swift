import SwiftUI

/// A subtle pulsing dot used to signal live background activity (agent streaming, etc).
struct PulsingDot: View {
    var color: Color = AppThemeConstants.brandPrimary
    var size: CGFloat = 8
    /// How the pulse looks: where it rests, how far it grows, how long one beat takes.
    var style: Style = .activity

    struct Style {
        let restingOpacity: Double
        let peakScale: CGFloat
        let beat: TimeInterval

        /// Background work — grows a little as it brightens.
        static let activity = Style(restingOpacity: 0.7, peakScale: 1.25, beat: 0.9)
        /// A live microphone — the same size throughout, dimming further.
        static let recording = Style(restingOpacity: 0.4, peakScale: 1, beat: 0.8)
    }

    /// Honoured here rather than at each call site, so a dot added somewhere new cannot
    /// reintroduce a forever-repeating animation for someone who asked for less movement.
    /// Safe to stop entirely because every row this dot appears in also says, in words, what
    /// is happening — see `IslandMotion`.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pulses = IslandMotion.allowsPulse(reduceMotion: reduceMotion)
        PulsingCircle(color: color, size: size, style: style, pulses: pulses)
            // A new identity when the setting changes, not a new value for the old one. The
            // dot outlives the setting — it is on screen while someone turns Reduce Motion on
            // — and a `repeatForever` already in flight is not stopped by assigning the value
            // it is heading for: the opacity is already "1" as far as SwiftUI is concerned,
            // so nothing replaced that animation and the dot kept fading. Rebuilding the
            // circle removes it with the view it was on, and brings the pulse back the same
            // way when the setting is turned off again.
            .id(pulses)
            .accessibilityHidden(true)
    }
}

private struct PulsingCircle: View {
    let color: Color
    let size: CGFloat
    let style: PulsingDot.Style
    let pulses: Bool

    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isExpanded ? style.peakScale : 1)
            // Still visible when it does not pulse, just still.
            .opacity(isExpanded || !pulses ? 1 : style.restingOpacity)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: style.beat).repeatForever(autoreverses: true)) {
                    isExpanded = true
                }
            }
    }
}
