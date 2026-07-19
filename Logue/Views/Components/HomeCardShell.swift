import SwiftUI

/// Shared card container used for both Document and Meeting cards in the home grid.
/// Provides hover shadow, teal border highlight, cursor change, and context menu.
///
/// The `content` closure receives `isHovered` so the card body can show/hide
/// hover-only UI like the "…" menu button.
struct HomeCardShell<Content: View, MenuContent: View>: View {
    let action: () -> Void
    /// Optional explicit accessibility label for the whole card. When present, this is what
    /// VoiceOver reads on the card button — much more reliable than letting SwiftUI synthesize
    /// from a complex nested content hierarchy (which macOS 26 fails to do, giving the card
    /// a completely empty AX title).
    var accessibilityLabel: String?
    var accessibilityHint: String?
    @ViewBuilder var content: (_ isHovered: Bool) -> Content
    @ViewBuilder var contextMenu: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        labelledButton
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .fill(AppThemeConstants.surfaceBackground)
                    .shadow(
                        color: .black.opacity(isHovered
                            ? AppThemeConstants.shadowOpacityHover
                            : AppThemeConstants.shadowOpacityDefault),
                        radius: isHovered
                            ? AppThemeConstants.shadowRadiusHover
                            : AppThemeConstants.shadowRadiusDefault,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .stroke(
                        isHovered ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity) : Color.clear,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isHovered)
            .contextMenu { contextMenu() }
            .overlay(HandCursorArea())
    }

    @ViewBuilder
    private var labelledButton: some View {
        let base = Button(action: action) {
            content(isHovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        // Apply a11y modifiers only when provided — empty-string labels override
        // SwiftUI's synthesis, so we must conditionally attach them.
        if let label = accessibilityLabel, let hint = accessibilityHint {
            base.accessibilityLabel(label).accessibilityHint(hint)
        } else if let label = accessibilityLabel {
            base.accessibilityLabel(label)
        } else if let hint = accessibilityHint {
            base.accessibilityHint(hint)
        } else {
            base
        }
    }
}
