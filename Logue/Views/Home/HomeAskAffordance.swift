import SwiftUI

/// The ✦ that turns a card into a question.
///
/// Rendered at all times rather than faded in on hover. Hover-only controls are
/// unreachable by keyboard and invisible to VoiceOver, so hovering brightens a control
/// that is already there instead of summoning one that was not.
struct HomeAskAffordance: View {
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: AppThemeConstants.iconSmall))
                .foregroundStyle(isHovering ? AppThemeConstants.accent : AppThemeConstants.mutedText)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                        .fill(
                            isHovering
                                ? AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight)
                                : Color.clear
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snappy) { isHovering = hovering }
        }
        .help("Ask Logue about this")
        .accessibilityLabel(accessibilityLabel)
    }
}
