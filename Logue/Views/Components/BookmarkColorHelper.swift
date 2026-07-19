import SwiftUI

extension BookmarkColor {
    var swiftUIColor: Color {
        switch self {
        case .red: AppThemeConstants.error
        case .orange: AppThemeConstants.warning
        case .yellow: AppThemeConstants.pinnedColor
        case .blue: AppThemeConstants.categoryBlue
        case .purple: AppThemeConstants.categoryPurple
        }
    }
}
