import SwiftUI

struct QuickPromptChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isPressed ? AppThemeConstants.brandPrimary.opacity(0.14) :
                    isHovered ? AppThemeConstants.brandPrimary.opacity(AppThemeConstants.opacityLight) : AppThemeConstants.quaternaryFill,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHovered ? AppThemeConstants.brandPrimary.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isHovered ? AppThemeConstants.brandPrimary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Sends this prompt to the AI assistant")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
