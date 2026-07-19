import SwiftUI

struct StatusFilterChip: View {
    let status: FactStatus
    let count: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(isSelected ? .white : status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                    .fill(isSelected ? status.color : status.color.opacity(AppThemeConstants.activeOpacity))
            )
        }
        .buttonStyle(.plain)
    }
}
