import SwiftUI

/// Small capsule badge for status indicators (Now, Soon, overdue, match type, etc).
///
/// Usage:
/// ```
/// StatusBadge(text: "Now", color: .red, showDot: true)
/// StatusBadge(text: "Soon", color: .orange, showDot: true)
/// StatusBadge(text: "Title match", color: AppThemeConstants.accent)
/// StatusBadge(text: "Recommended", color: AppThemeConstants.accent)
/// ```
struct StatusBadge: View {
    let text: String
    var color: Color = AppThemeConstants.accent
    var showDot: Bool = false
    var font: Font = .caption2

    var body: some View {
        HStack(spacing: 4) {
            if showDot {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(font.weight(.bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(AppThemeConstants.opacityLight), in: Capsule())
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
