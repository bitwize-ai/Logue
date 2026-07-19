import SwiftUI

struct TypingIndicatorView: View {
    @State private var animPhase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animPhase ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: animPhase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AppThemeConstants.quaternaryFill,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXLarge)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusXLarge)
                .strokeBorder(Color.primary.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animPhase = true }
        .accessibilityLabel("AI is typing")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
