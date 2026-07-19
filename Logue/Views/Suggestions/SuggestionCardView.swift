import SwiftUI

/// Individual suggestion card — matches the inline popover style.
struct SuggestionCardView: View {
    let suggestion: Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void
    var onSelect: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Explanation + dismiss ─────────────────────────────────
            HStack(alignment: .top) {
                Text(suggestion.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.4)
                .help("Dismiss")
            }

            // ── Replacement preview (strikethrough → arrow → replacement) ──
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

            // ── Action buttons ────────────────────────────────────────
            HStack(spacing: 8) {
                if suggestion.replacement != suggestion.original {
                    Button("Accept") { onAccept() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppThemeConstants.accent)
                        .controlSize(.small)
                }
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(14)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(
                    .separator.opacity(isHovered ? 1 : 0.5),
                    lineWidth: 0.5
                )
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: AppThemeConstants.radiusLarge,
                bottomLeadingRadius: AppThemeConstants.radiusLarge
            )
            .fill(suggestion.type.categoryColor)
            .frame(width: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestion: replace \(suggestion.original) with \(suggestion.replacement)")
        .accessibilityHint(suggestion.explanation)
    }
}
