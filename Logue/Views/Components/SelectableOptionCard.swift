import SwiftUI

/// Selectable card used for option pickers (recording mode, meeting template, theme).
///
/// Usage:
/// ```
/// // Full card with description
/// SelectableOptionCard(
///     icon: "mic.fill",
///     title: "In Person",
///     description: "Uses your Mac's microphone",
///     isSelected: selectedMode == .inPerson
/// ) {
///     selectedMode = .inPerson
/// }
///
/// // Compact chip-style card (no description, no checkmark)
/// SelectableOptionCard(
///     icon: "briefcase",
///     title: "Business",
///     isSelected: selectedTemplate == .business,
///     style: .compact
/// ) {
///     selectedTemplate = .business
/// }
/// ```
struct SelectableOptionCard: View {
    let icon: String
    let title: String
    var description: String?
    let isSelected: Bool
    var style: Style = .full
    let action: () -> Void

    enum Style {
        /// Full-width card with optional description and checkmark.
        case full
        /// Compact chip-style for grid layouts.
        case compact
    }

    var body: some View {
        Button(action: action) {
            switch style {
            case .full:
                fullContent
            case .compact:
                compactContent
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fullContent: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundColor(isSelected ? AppThemeConstants.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppThemeConstants.accent)
            }
        }
        .padding(12)
        .background(
            isSelected
                ? AppThemeConstants.accent.opacity(AppThemeConstants.hoverOpacity)
                : AppThemeConstants.surfaceBackground,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .stroke(
                    isSelected
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? AppThemeConstants.accent.opacity(AppThemeConstants.activeOpacity)
                : AppThemeConstants.surfaceBackground,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                .stroke(
                    isSelected
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity)
                        : Color.primary.opacity(AppThemeConstants.opacityLight),
                    lineWidth: 1
                )
        )
        .foregroundStyle(isSelected ? AppThemeConstants.accent : .primary)
    }
}
