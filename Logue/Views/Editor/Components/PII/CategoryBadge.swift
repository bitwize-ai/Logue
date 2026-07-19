import SwiftUI

struct CategoryBadge: View {
    let category: PIICategory
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.caption2)
                Text(category.rawValue)
                    .font(.caption)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isEnabled
                    ? category.risk.color.opacity(isHovered ? 0.18 : 0.12)
                    : AppThemeConstants.quaternaryFill.opacity(isHovered ? 0.8 : 1),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isEnabled
                            ? category.risk.color.opacity(0.4)
                            : Color.primary.opacity(AppThemeConstants.opacityLight),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isEnabled ? category.risk.color : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityLabel("\(category.rawValue) category")
        .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint("Double-tap to toggle")
        .accessibilityAddTraits(isEnabled ? .isSelected : [])
    }
}
