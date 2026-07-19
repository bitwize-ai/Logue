import SwiftUI

/// Compact card shown inside an NSPopover when the user clicks an underlined word.
struct InlineSuggestionPopoverView: View {
    let suggestion: Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Type badge row ──────────────────────────────────────────────
            HStack(spacing: 6) {
                Circle()
                    .fill(suggestion.type.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(suggestion.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(suggestion.type.swiftUIColor)
                Spacer()
            }

            // ── Explanation ─────────────────────────────────────────────────
            Text(suggestion.explanation)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // ── Replacement preview (only when there's a meaningful fix) ────
            if suggestion.replacement != suggestion.original,
               !suggestion.replacement.isEmpty
            {
                HStack(spacing: 6) {
                    Text(suggestion.original)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .strikethrough(color: .secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(suggestion.replacement)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppThemeConstants.accent)
                }
                .padding(6)
                .background(
                    AppThemeConstants.accent.opacity(AppThemeConstants.hoverOpacity),
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                )
            }

            Divider()

            // ── Action buttons ──────────────────────────────────────────────
            HStack(spacing: 8) {
                if suggestion.replacement != suggestion.original {
                    Button("Accept") { onAccept() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppThemeConstants.accent)
                        .controlSize(.small)
                        .accessibilityLabel("Accept suggestion")
                        .accessibilityHint("Applies the suggested replacement to your text")
                }
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                    .accessibilityLabel("Dismiss suggestion")
                    .accessibilityHint("Closes this suggestion without applying it")
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
