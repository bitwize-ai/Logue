import SwiftUI

/// The toolbar button that reveals a library panel.
///
/// The panel itself is rendered inside the surface's content view — see the `trailingPanel`
/// closure on `MeetingListContentView` / `DocumentListContentView` — so that it begins below
/// that view's own header instead of running up alongside it. This modifier only supplies the
/// control that opens it.
struct LibraryPanelToggle: ViewModifier {
    @Binding var isCollapsed: Bool
    let panel: LibraryPanel
    /// Shown on the button. This is the signal that used to be a sidebar badge, so it is the
    /// one thing moving the surface into a panel must not lose.
    var badgeCount: Int?

    func body(content: Content) -> some View {
        content
            .measuringWorkspaceWidth()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCollapsed.toggle()
                    } label: {
                        Image(systemName: panel.symbolName)
                            .overlay(alignment: .topTrailing) {
                                if let badgeCount, badgeCount > 0 {
                                    badge(badgeCount)
                                }
                            }
                    }
                    .help(panel.title)
                    .accessibilityLabel(accessibilityLabel)
                }
            }
    }

    private func badge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(AppThemeConstants.accent, in: Capsule())
            // Pushed clear of the glyph so it reads as a badge rather than part of the icon.
            .offset(x: 7, y: -6)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        guard let badgeCount, badgeCount > 0 else { return panel.title }
        return "\(panel.title), \(badgeCount) waiting"
    }
}

extension View {
    func libraryPanelToggle(
        isCollapsed: Binding<Bool>, panel: LibraryPanel, badgeCount: Int? = nil
    ) -> some View {
        modifier(
            LibraryPanelToggle(isCollapsed: isCollapsed, panel: panel, badgeCount: badgeCount)
        )
    }
}
