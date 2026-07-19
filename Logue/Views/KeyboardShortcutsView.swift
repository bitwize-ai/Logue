import SwiftUI

/// Standalone window that lists all keyboard shortcuts for Logue.
struct KeyboardShortcutsView: View {
    @State private var shortcutManager = ShortcutManager.shared

    private var shortcuts: [(label: String, shortcut: String)] {
        [
            ("Ask Logue", shortcutManager.commandCenterShortcut.displayString),
            ("New Document", "⌘N"),
            ("New Meeting", "⇧⌘N"),
            ("Export Meeting", "⌘E"),
            ("Settings", "⌘,"),
            ("Close Window", "⌘W"),
            ("Quit Logue", "⌘Q"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shortcuts, id: \.label) { item in
                ShortcutListRow(label: item.label, shortcut: item.shortcut)
            }

            Spacer()
        }
        .padding(AppThemeConstants.paddingXXLarge)
        .frame(width: 380, height: 320)
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
