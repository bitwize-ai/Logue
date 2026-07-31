import SwiftUI

/// Standalone window that lists all keyboard shortcuts for Logue.
struct KeyboardShortcutsView: View {
    @State private var shortcutManager = ShortcutManager.shared

    private var shortcuts: [(label: String, shortcut: String)] {
        [
            ("Ask Logue", shortcutManager.commandCenterShortcut.displayString),
            ("New Document", "⌘N"),
            ("New Meeting", "⇧⌘N"),
            ("Command Palette", "⌘K"),
            ("Quick Open", "⌘P"),
            ("Zoom In", "⌘+ or ⌘="),
            ("Zoom Out", "⌘-"),
            ("Actual Size", "⌘0"),
            (EditorLayoutMode.editorOnly.label, "⌘1"),
            (EditorLayoutMode.editorAndList.label, "⌘2"),
            (EditorLayoutMode.allPanels.label, "⌘3"),
            ("Export Meeting", "⌘E"),
            ("Settings", "⌘,"),
            ("Close Window", "⌘W"),
            ("Quit Logue", "⌘Q"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shortcuts, id: \.label) { item in
                    ShortcutListRow(label: item.label, shortcut: item.shortcut)
                }
            }
            .padding(AppThemeConstants.paddingXXLarge)
        }
        // Scrolls rather than growing the window: the list is long enough now that a fixed
        // height would clip the last rows on a short display.
        .frame(width: 400, height: 420)
    }
}

// MARK: - Row

private struct ShortcutListRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)

            Spacer()

            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                        .fill(AppThemeConstants.quaternaryFill)
                )
        }
        .padding(.vertical, 8)

        Divider()
    }
}
