import SwiftUI

/// Capsule-shaped chip for filtering, tags, or keyword display.
///
/// Usage:
/// ```
/// // Tag filter bar
/// FilterChip(label: "All", isSelected: selectedTag == nil) {
///     selectedTag = nil
/// }
///
/// // Read-only keyword chip
/// FilterChip(label: keyword, isSelected: false, style: .tinted)
///
/// // Removable tag chip
/// FilterChip(label: tag, isSelected: false, style: .removable) {
///     removeTag(tag)
/// }
/// ```
struct FilterChip: View {
    let label: String
    var isSelected: Bool = false
    var style: Style = .toggle
    /// Optional override color; when nil, falls back to accent.
    var tintColor: Color?
    var action: (() -> Void)?

    enum Style {
        /// Toggle-style chip — filled accent background when selected.
        case toggle
        /// Always shows a tinted accent background (for read-only keywords/topics).
        case tinted
        /// Shows an "x" button for removal.
        case removable
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                if case .removable = style {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
            // Setting the label INSIDE the Button's composed content forces SwiftUI to use it
            // as the AX title. Setting it OUTSIDE (on the Button itself) was being overridden
            // by the accessibility-hint in macOS 26 SwiftUI — the hint bled into the title slot
            // in the AX tree, so every chip read as "Double tap to select".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(style == .removable ? "Double tap to remove" : "Double tap to select")
    }

    private var resolvedTint: Color {
        tintColor ?? AppThemeConstants.accent
    }

    private var backgroundColor: Color {
        switch style {
        case .toggle:
            isSelected
                ? resolvedTint.opacity(AppThemeConstants.activeOpacity)
                : AppThemeConstants.surfaceBackground
        case .tinted, .removable:
            resolvedTint.opacity(AppThemeConstants.opacityLight)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .toggle:
            isSelected ? resolvedTint : .secondary
        case .tinted, .removable:
            resolvedTint
        }
    }
}
