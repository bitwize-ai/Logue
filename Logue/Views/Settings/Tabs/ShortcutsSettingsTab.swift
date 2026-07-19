import SwiftUI

/// Phase A0: a flat reference table of every keyboard shortcut Logue exposes.
/// Read-only for now (rebinding requires a dedicated `ShortcutManager` slot
/// that the menu commands honor — left for a follow-up). Lists the same set
/// the plan promised so the user can discover them all in one place.
struct ShortcutsSettingsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(ShortcutGroup.all) { group in
                    section(group)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keyboard Shortcuts")
                .font(.title3.weight(.semibold))
            Text(
                "All shortcuts are listed below. Rebinding lands in a future update — open an issue if a default conflicts with another tool you use."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Group rendering

    private func section(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(group.entries) { entry in
                shortcutRow(entry)
            }
        }
    }

    private func shortcutRow(_ entry: ShortcutEntry) -> some View {
        HStack {
            Text(entry.label)
                .font(.callout)
            Spacer()
            Text(entry.combo)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Data

private struct ShortcutEntry: Identifiable {
    let id = UUID()
    let label: String
    let combo: String
}

private struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let entries: [ShortcutEntry]

    static let all: [ShortcutGroup] = [
        ShortcutGroup(title: "Chat", entries: [
            ShortcutEntry(label: "New chat", combo: "⌘N"),
            ShortcutEntry(label: "New chat (Ask Logue)", combo: "⌘L"),
            ShortcutEntry(label: "Focus chat input", combo: "⌘⇧L"),
            ShortcutEntry(label: "Send", combo: "⌘⏎"),
            ShortcutEntry(label: "Stop generation", combo: "Esc"),
            ShortcutEntry(label: "Copy last assistant message", combo: "⌘⇧C"),
            ShortcutEntry(label: "Regenerate last response", combo: "⌘⇧R"),
        ]),
        ShortcutGroup(title: "Navigation", entries: [
            ShortcutEntry(label: "Command palette", combo: "⌘K"),
            ShortcutEntry(label: "Focus conversation search", combo: "⌘/"),
            ShortcutEntry(label: "Toggle sidebar", combo: "⌘S"),
            ShortcutEntry(label: "Settings", combo: "⌘,"),
            ShortcutEntry(label: "Previous / next message", combo: "⌘↑ / ⌘↓"),
        ]),
        ShortcutGroup(title: "Cross-app (Phase D)", entries: [
            ShortcutEntry(label: "Inline writing assistant", combo: "⌘⌃I"),
            ShortcutEntry(label: "Menu-bar companion (planned)", combo: "⌥Space"),
        ]),
        ShortcutGroup(title: "Conversation list", entries: [
            ShortcutEntry(label: "Export selected conversation", combo: "⌘E"),
            ShortcutEntry(label: "Branch from selected message", combo: "⌘;"),
        ]),
    ]
}
