import SwiftUI

/// A subtle pulsing dot used to signal live background activity (agent streaming, etc).
struct PulsingDot: View {
    var color: Color = AppThemeConstants.brandPrimary
    var size: CGFloat = 8

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0.7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    scale = 1.25
                    opacity = 1.0
                }
            }
            .accessibilityHidden(true)
    }
}
