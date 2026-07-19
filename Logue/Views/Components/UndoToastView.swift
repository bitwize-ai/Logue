import SwiftUI

/// Floating toast with undo action, shown briefly after destructive actions.
struct UndoToastView: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.body)
                .foregroundStyle(AppThemeConstants.accent)

            Text(message)
                .font(.subheadline)

            Spacer()

            Button("Undo") {
                onUndo()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.accent)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(
                    color: .black.opacity(AppThemeConstants.toastShadowOpacity),
                    radius: AppThemeConstants.toastShadowRadius,
                    y: AppThemeConstants.toastShadowY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(Color.primary.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
