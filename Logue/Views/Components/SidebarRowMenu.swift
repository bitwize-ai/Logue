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

    /// Reported back so a row can move its own trailing content out of the button's way — an item
    /// count, a date — in step with the button rather than a beat before or after it.
    let revealed: Binding<Bool>?

    /// Whether the list already paints this row as the selected one.
    let isSelected: Bool

    @State private var isHovering = false
    @State private var isMenuOpen = false
    @State private var hoverOutTask: Task<Void, Never>?

    /// The button is shown while the pointer is over the row, and stays shown while its own menu
    /// is up: macOS hands the event stream to the menu, so hover would otherwise read as "gone"
    /// and the button would vanish out from under the menu it just opened.
    private var isRevealed: Bool { isHovering || isMenuOpen }

    func body(content: Content) -> some View {
        content
            // Rows whose content is narrower than the row — a plain `Label` in the space tree —
            // would otherwise anchor the button just past their text rather than at the edge.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Without this the highlight is only as tall as the text and reads as a bar drawn
            // through the row rather than as the row itself lighting up.
            .padding(.vertical, AppThemeConstants.paddingXSmall)
            // The whole row lights up, not just the button — the button appearing on its own read
            // as a thing floating over the list rather than as part of the row under the pointer.
            .background(rowBackground)
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
            .onChange(of: isRevealed) { _, nowRevealed in
                revealed?.wrappedValue = nowRevealed
            }
            .onDisappear {
                hoverOutTask?.cancel()
                // A row scrolled out mid-hover never gets its hover-out, and the state is the
                // parent's, so it would come back still believing it was under the pointer.
                revealed?.wrappedValue = false
            }
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
                .font(.callout.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // The list tints its rows, which would paint the glyph in the accent colour and read as
        // something to act on rather than a way in to the actions.
        .tint(Color.secondary)
        .padding(.trailing, AppThemeConstants.paddingSmall)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isRevealed)
        .accessibilityLabel("More actions")
        .accessibilityHint("Opens the same actions as Control-clicking this row")
    }

    /// The row's own hover highlight: the accent the selected row is painted in, at the lighter
    /// end of it, so hovering reads as the same gesture as selecting rather than a second colour.
    ///
    /// The selected row is skipped — it already carries that fill, and laying another over it
    /// would make selected-and-hovered look like a third state. Drawn behind the row's content, so
    /// a row that paints itself — a trash card — keeps the look it has.
    private var rowBackground: some View {
        let showsHighlight = isRevealed && !isSelected
        return RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
            .fill(AppThemeConstants.accent.opacity(showsHighlight ? AppThemeConstants.hoverOpacity : 0))
            .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: showsHighlight)
    }

}

extension View {
    /// Gives a sidebar row a hover-revealed "⋯" button and the identical right-click menu.
    ///
    /// Replaces a bare `.contextMenu { … }` on rows — pass exactly what that took.
    ///
    /// Pass `revealed` on a row that draws something at its own trailing edge, and fade that
    /// content out on it: the button has no backdrop, so the two would otherwise sit on top of
    /// each other.
    /// Pass `isSelected` so the hover highlight stands down on the row the list already paints.
    func sidebarRowMenu(
        isSelected: Bool = false,
        revealed: Binding<Bool>? = nil,
        @ViewBuilder _ menu: @escaping () -> some View
    ) -> some View {
        modifier(SidebarRowMenu(menu: menu, revealed: revealed, isSelected: isSelected))
    }
}

extension Binding where Value == UUID? {
    /// Whether `id` is the row currently showing its "⋯".
    ///
    /// A list keeps one of these for all its rows: a row built by a `ForEach` is a value the list
    /// rebuilds, so it cannot hold the state itself.
    func isRevealed(_ id: UUID) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue == id },
            set: { isRevealed in
                if isRevealed {
                    wrappedValue = id
                } else if wrappedValue == id {
                    // Guarded: rows hand back `false` as the pointer moves on, and the row being
                    // left reports after the row being entered, which would clear it again.
                    wrappedValue = nil
                }
            }
        )
    }
}
