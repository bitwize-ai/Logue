import SwiftUI

/// Standardized empty/placeholder state shown when a panel has no content yet.
///
/// Usage:
/// ```
/// EmptyStateView(
///     icon: "checklist",
///     title: "No action items",
///     description: "Action items will be extracted when you generate a summary.",
///     actionLabel: "Generate Summary",
///     action: { generateSummary() }
/// )
/// ```
struct EmptyStateView: View {
    let icon: String
    let title: String
    var description: String?
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
