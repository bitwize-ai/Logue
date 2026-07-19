import SwiftUI

/// Standard card container for insight/stats cards.
/// Provides consistent padding, background, corner radius, and border.
struct InsightCardShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(AppThemeConstants.paddingLarge)
            .background(
                AppThemeConstants.surfaceBackground,
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                    .stroke(AppThemeConstants.borderColor, lineWidth: 1)
            )
    }
}
