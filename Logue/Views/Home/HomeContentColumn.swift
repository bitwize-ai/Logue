import SwiftUI

/// Holds a view to Home's reading column: capped at `contentColumnWidth`, centred in
/// whatever space it is given, with the page margin outside the cap.
///
/// The prompt bar, the greeting and every card go through this one modifier. Written out
/// by hand it is three modifiers in a specific order, and it appeared four times across
/// two files — one of those copies had drifted to a literal `24` where the others used
/// the token, so retuning the token would have moved the landing prompt bar and left the
/// post-send one behind, sliding the input sideways on first send.
struct HomeContentColumn: ViewModifier {
    var alignment: Alignment = .center

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: AppThemeConstants.contentColumnWidth, alignment: alignment)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppThemeConstants.paddingXXLarge)
    }
}

extension View {
    /// See `HomeContentColumn`.
    func homeContentColumn(alignment: Alignment = .center) -> some View {
        modifier(HomeContentColumn(alignment: alignment))
    }
}
