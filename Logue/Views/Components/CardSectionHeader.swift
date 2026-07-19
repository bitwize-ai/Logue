import SwiftUI

/// Reusable section/card header with an SF Symbol icon and title.
struct CardSectionHeader: View {
    let icon: String
    let title: String
    var color: Color = AppThemeConstants.accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
