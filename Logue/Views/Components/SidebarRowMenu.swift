import AppKit
import SwiftUI

/// A sidebar row's actions, reachable two ways from one definition.
///
/// The actions used to be right-click only, which is invisible — nothing on a row says they
/// exist, so people who never thought to Control-click never found Pin, Rename or Trash at all.
/// This reveals a "⋯" button at the row's trailing edge on hover and opens the *same* menu from
/// it. One `@ViewBuilder` feeds both paths, so they cannot drift apart, and right-click keeps
/// working exactly as before for everyone already used to it.
struct SidebarRowMenu<MenuContent: View>: ViewModifier {
    let menu: () -> MenuContent

    @State private var isHovering = false
    @State private var isMenuOpen = false
    @State private var hoverOutTask: Task<Void, Never>?

    /// The button is shown while the pointer is over the row, and stays shown while its own menu
    /// is up: macOS hands the event stream to the menu, so hover would otherwise read as "gone"
    /// and the button would vanish out from under the menu it just opened.
    private var isRevealed: Bool { isHovering || isMenuOpen }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) { menuButton }
            .contextMenu { menu() }
            .onHover { hovering in
                hoverOutTask?.cancel()
                guard !hovering else {
                    isHovering = true
                    return
                }
                // Held briefly rather than cleared outright, so a click on the button is still
                // "hovering" by the time the menu reports that it began tracking. Without the
                // gap the two events race and the button blinks out as the menu appears.
                hoverOutTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.rowHoverOut)
                    guard !Task.isCancelled else { return }
                    isHovering = false
                }
            }
            .onDisappear { hoverOutTask?.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                if isHovering { isMenuOpen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                isMenuOpen = false
            }
    }

    private var menuButton: some View {
        Menu {
            menu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                // Opaque enough to sit over whatever the row already draws at its trailing edge
                // (a date, a count) without the two reading as one smudge.
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, 2)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isRevealed)
        .accessibilityLabel("More actions")
        .accessibilityHint("Opens the same actions as Control-clicking this row")
    }
}

extension View {
    /// Gives a sidebar row a hover-revealed "⋯" button and the identical right-click menu.
    ///
    /// Replaces a bare `.contextMenu { … }` on rows — pass exactly what that took.
    func sidebarRowMenu(@ViewBuilder _ menu: @escaping () -> some View) -> some View {
        modifier(SidebarRowMenu(menu: menu))
    }
}
