import AppKit
import SwiftUI

/// Phase A0: a frameless 600pt floating "Ask Logue" panel summoned from
/// anywhere via ⌥Space. Mirrors the pattern Raycast / ChatGPT desktop use —
/// always-available agent without leaving the foreground app.
///
/// The window is non-activating, floats above other windows, and auto-hides
/// when it loses key focus. Internally it embeds a slim chat surface that
/// shares state with the main window via `AgentConversationStore.shared`,
/// so a conversation started in the companion is visible in the main app.
@MainActor
final class MenuBarCompanionController {
    static let shared = MenuBarCompanionController()

    private var window: MenuBarCompanionWindow?
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?

    private init() {}

    /// Wires the ⌥Space hotkey via global + local NSEvent monitors. Mirrors the
    /// pattern used by InlineAssistant — global fires when other apps own the
    /// foreground, local fires when Logue itself does.
    func install() {
        let mask: NSEvent.ModifierFlags = [.option]
        // keyCode 49 = Space.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask
            else { return }
            Task { @MainActor in MenuBarCompanionController.shared.toggle() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask
            else { return event }
            Task { @MainActor in MenuBarCompanionController.shared.toggle() }
            return nil
        }
    }

    func uninstall() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    func toggle() {
        if let window, window.isVisible {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        let win = window ?? makeWindow()
        window = win
        // Center on the active screen with a slight upward bias.
        if let screen = NSScreen.main {
            let frame = win.frame
            let originX = screen.frame.midX - frame.width / 2
            let originY = screen.frame.midY - frame.height / 2 + 80
            win.setFrameOrigin(NSPoint(x: originX, y: originY))
        }
        win.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> MenuBarCompanionWindow {
        let view = MenuBarCompanionView { [weak self] in
            self?.dismiss()
        }
        let win = MenuBarCompanionWindow(rootView: view)
        win.delegate = WindowDelegate.shared
        return win
    }
}

// MARK: - Window

final class MenuBarCompanionWindow: NSPanel {
    init(rootView: MenuBarCompanionView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool {
        true
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()
    func windowDidResignKey(_ notification: Notification) {
        MenuBarCompanionController.shared.dismiss()
    }
}

// MARK: - View

struct MenuBarCompanionView: View {
    let onDismiss: () -> Void
    @State private var prompt: String = ""
    @State private var coordinator = AgentCoordinator.shared
    @State private var conversationStore = AgentConversationStore.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            inputCard
            Divider()
            recentRow
        }
        .padding(14)
        .background(.regularMaterial)
        .onExitCommand {
            onDismiss()
        }
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text("Ask Logue")
                .font(.callout.weight(.semibold))
            TrustChip(variant: .compact, label: UICopy.Trust.local)
            Spacer()
            Text("⌥Space to toggle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask anything…", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .font(.body)
                .onSubmit { send() }
            HStack {
                Text("Sends to your active conversation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Send") { send() }
                    .keyboardShortcut(.return)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            let recent = conversationStore.conversations
                .filter { !$0.isArchived }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(3)
            if recent.isEmpty {
                Text("No conversations yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(recent), id: \.id) { conv in
                    Button {
                        conversationStore.selectedConversationID = conv.id
                        NotificationCenter.default.post(name: .chatNewConversation, object: nil)
                        onDismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left").font(.caption2).foregroundStyle(.secondary)
                            Text(conv.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func send() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Make sure we have an active conversation to receive the message.
        let convID: UUID
        if let existing = conversationStore.selectedConversationID {
            convID = existing
        } else {
            let new = conversationStore.createConversation()
            conversationStore.selectedConversationID = new.id
            convID = new.id
        }
        prompt = ""
        // Hand off to the main window so the user can watch the response stream.
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .chatNewConversation, object: nil)
        coordinator.send(message: trimmed, conversationID: convID)
        onDismiss()
    }
}
