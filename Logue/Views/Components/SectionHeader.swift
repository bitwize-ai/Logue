import SwiftUI

/// Standardized section heading with icon + title, used across summary panels, digest views, etc.
///
/// Usage:
/// ```
/// SectionHeader(title: "Key Decisions", icon: "checkmark.seal")
/// SectionHeader(title: "Topics", icon: "tag") {
///     Text("5 topics").font(.caption).foregroundStyle(.tertiary)
/// }
/// ```
struct SectionHeader<Trailing: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(AppThemeConstants.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
        trailing = { EmptyView() }
    }
}
