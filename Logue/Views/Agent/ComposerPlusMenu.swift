import SwiftUI

/// The `+` at the left of a composer: attach a file, arm a per-send mode, or open the
/// tool settings.
///
/// Lifted out of `InputBarView` so the Command Center island offers the same menu rather
/// than a row of its own icon buttons. Before this the island spelled three of these
/// items out as separate glyphs and had no way to reach tool settings at all — the one
/// item on #61's list of shared composer parts that was still redrawn per surface.
///
/// **Why the flags are keys rather than bindings.** On macOS a SwiftUI `Menu` drops
/// `Button.action` closures and swallows `.toggle()` against an `@Binding` in its
/// deferred-close pipeline; binding a `Toggle` straight to `@AppStorage` is the only
/// shape that reliably survives it. So this takes *key names* and declares its own
/// storage, which lets each surface keep its own value — the island must not share the
/// main window's one-shot flags, because it clears them after every send and would
/// disarm a chip the user had set up over there.
struct ComposerPlusMenu: View {
    /// Colours for the `+` glyph and its backing circle, so the main window's light card
    /// and the island's dark pill can each look like themselves.
    struct Style {
        let foreground: Color
        let background: Color
        let border: Color

        static let mainWindow = Style(
            foreground: .primary,
            background: Color.secondary.opacity(0.12),
            border: Color.primary.opacity(0.10)
        )

        /// The island is a dark HUD over another app, so `.primary` would be wrong.
        static let island = Style(
            foreground: .white.opacity(0.85),
            background: Color.white.opacity(0.10),
            border: Color.white.opacity(0.12)
        )
    }

    let isDisabled: Bool
    let onAttach: () -> Void
    var style: Style = .mainWindow

    @AppStorage private var isWebSearchOnce: Bool
    @AppStorage private var isDeepResearchOnce: Bool

    init(
        webSearchKey: String,
        deepResearchKey: String,
        isDisabled: Bool,
        style: Style = .mainWindow,
        onAttach: @escaping () -> Void
    ) {
        self.isDisabled = isDisabled
        self.style = style
        self.onAttach = onAttach
        _isWebSearchOnce = AppStorage(wrappedValue: false, webSearchKey)
        _isDeepResearchOnce = AppStorage(wrappedValue: false, deepResearchKey)
    }

    var body: some View {
        Menu {
            Button(action: onAttach) {
                Label(UICopy.Input.addFiles, systemImage: "paperclip")
            }
            .keyboardShortcut("u", modifiers: .command)

            // Toggles inside a Menu render as native NSMenuItems with a checkmark when
            // on. See the note on this type for why they bind `@AppStorage` rather than
            // a `@Binding<Bool>` handed in by the caller.
            Toggle(isOn: $isWebSearchOnce) {
                Label(UICopy.Input.searchTheWeb, systemImage: "globe")
            }
            Toggle(isOn: $isDeepResearchOnce) {
                Label(UICopy.Input.deepResearchMenu, systemImage: "sparkle.magnifyingglass")
            }

            Divider()

            Button {
                AppDelegate.openToolSettings()
            } label: {
                Label(UICopy.Input.toolSettings, systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(style.foreground)
                .frame(width: 28, height: 28)
                .background(Circle().fill(style.background))
                .overlay(Circle().strokeBorder(style.border, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(UICopy.Input.composerMenuHelp)
        .disabled(isDisabled)
        .accessibilityLabel(UICopy.Input.composerMenuLabel)
    }
}
