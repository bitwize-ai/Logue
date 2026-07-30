import SwiftUI

extension Notification.Name {
    static let openMeetingExportPanel = Notification.Name("openMeetingExportPanel")

    static let openSettingsGeneral = Notification.Name("openSettingsGeneral")
    static let openSettingsAboutAndCheckUpdates = Notification.Name("openSettingsAboutAndCheckUpdates")
    static let openKeyboardShortcutsWindow = Notification.Name("openKeyboardShortcutsWindow")
    static let openResourceUsageWindow = Notification.Name("openResourceUsageWindow")
    static let openReportBugWindow = Notification.Name("openReportBugWindow")
    /// Asked for by name from the Help menu, rather than offered after an update.
    static let showWhatsNew = Notification.Name("showWhatsNew")

    /// Phase A: chat-first shortcuts.
    /// `Cmd+L` — start a new chat (and switch sidebar to Ask Logue).
    static let chatNewConversation = Notification.Name("chatNewConversation")
    /// `Cmd+Shift+L` — switch to Ask Logue and focus the input field.
    static let chatFocusInput = Notification.Name("chatFocusInput")
}

@main
struct LogueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Editor zoom multiplier, shared with the editor through AppStorage so both
    /// scenes stay in sync without a separate observable.
    @AppStorage(AppConstants.UserDefaultsKeys.editorZoomScale) private var zoomScale: Double =
        AppConstants.Editor.defaultZoom

    init() {
        // Must run before any store singleton resolves its Application Support
        // directory or reads UserDefaults — see SandboxContainerMigrator.
        SandboxContainerMigrator.migrateIfNeeded()
    }

    var body: some Scene {
        // ── Main document window ──────────────────────────────────────────────
        WindowGroup("Logue") {
            AppRootView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    DocumentStore.shared.createDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Meeting") {
                    MeetingStore.shared.createMeeting()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("New Chat") {
                    NotificationCenter.default.post(name: .chatNewConversation, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Chat Input") {
                    NotificationCenter.default.post(name: .chatFocusInput, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandGroup(after: .importExport) {
                Button("Export Meeting…") {
                    NotificationCenter.default.post(name: .openMeetingExportPanel, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button(
                    action: { HelpMenuActions.checkForUpdates() },
                    label: { Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") }
                )
            }

            CommandGroup(after: .pasteboard) {
                Button("Paste Without Formatting") {
                    NSApp.sendAction(#selector(NSTextView.pasteAsPlainText(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Zoom In") { applyZoom { $0.zoomIn() } }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { applyZoom { $0.zoomOut() } }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { applyZoom { $0.reset() } }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }

            CommandGroup(replacing: .help) {
                Button(UICopy.WhatsNew.menuItem) { HelpMenuActions.showWhatsNew() }

                Divider()

                Button("Documentation") { HelpMenuActions.openDocumentation() }
                Button("Keyboard Shortcuts") { HelpMenuActions.openKeyboardShortcuts() }

                Divider()

                Button("Report Bug / Issue") { HelpMenuActions.reportBug() }
                Button("Contact Support") { HelpMenuActions.contactSupport() }
                Menu("Troubleshooting") {
                    Button("See Resource Usage") { HelpMenuActions.openResourceUsage() }
                    Menu("Clear Cache") {
                        Button("Clear Cache and Quit") { TroubleshootingActions.clearCacheAndQuit() }
                        Button("Clear Cache and Restart") { TroubleshootingActions.clearCacheAndRestart() }
                    }
                    Button("Reset Application Data") { TroubleshootingActions.resetApplicationData() }
                }

                Divider()

                Button("Privacy Policy") { HelpMenuActions.openPrivacyPolicy() }
                Button("Terms of Service") { HelpMenuActions.openTermsOfService() }

                Divider()

                Button("Join Us on LinkedIn") { HelpMenuActions.joinLinkedIn() }
                Button("About Us") { HelpMenuActions.openAboutUs() }
            }
        }

        // ── Settings window ───────────────────────────────────────────────────
        Settings {
            SettingsRootView()
        }
    }

    /// Applies a zoom mutation through `EditorZoom` so clamping lives in one place.
    private func applyZoom(_ mutate: (inout EditorZoom) -> Void) {
        var zoom = EditorZoom()
        zoom.scale = zoomScale
        mutate(&zoom)
        zoomScale = zoom.scale
    }
}

// MARK: - Themed Root Views

/// Identifies a pending What's New sheet.
///
/// The sheet is item-driven rather than boolean-driven because it carries which
/// releases to show, and because two boolean `.sheet` modifiers on one view do not
/// reliably both present.
private struct WhatsNewSheetItem: Identifiable {
    let id = UUID()
    let mode: WhatsNewView.Mode
}

/// Wraps the main window, injects all environments, follows system appearance.
private struct AppRootView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.openSettings) private var openSettings
    @State private var whatsNew: WhatsNewSheetItem?

    var body: some View {
        MainWindowView()
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsGeneral)) { _ in
                openSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsAboutAndCheckUpdates)) { _ in
                SettingsNavigator.shared.pendingTab = .about
                SettingsNavigator.shared.pendingCheckForUpdates = true
                openSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in
                whatsNew = WhatsNewSheetItem(mode: .latestNotes)
            }
            .environment(ModelManager.shared)
            .environment(DocumentStore.shared)
            .environment(MeetingStore.shared)
            .environment(SpaceStore.shared)
            .environment(RecordingSessionManager.shared)
            .environment(TemplateStore.shared)
            .environment(CalendarManager.shared)
            .sheet(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: {
                    if !$0 {
                        hasCompletedOnboarding = true
                    }
                }
            )) {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .environment(ModelManager.shared)
                .interactiveDismissDisabled()
            }
            .task {
                // The tour belongs to a fresh install and waits for the wizard; only
                // release notes are owed to someone who has been here before.
                guard hasCompletedOnboarding else { return }
                if case let .whatsNew(releases) = WhatsNewGate.presentationForLaunch() {
                    whatsNew = WhatsNewSheetItem(mode: .whatsNew(releases))
                }
            }
            .onChange(of: hasCompletedOnboarding) { wasCompleted, isCompleted in
                // False to true happens once, when a new install finishes the wizard —
                // nothing else sets this, and a data reset deliberately preserves it.
                guard !wasCompleted, isCompleted else { return }
                Task {
                    // AppKit drops a sheet requested while the previous one is still
                    // animating away, silently.
                    try? await Task.sleep(for: AppConstants.Delays.sheetHandoff)
                    whatsNew = WhatsNewSheetItem(mode: .discover)
                }
            }
            .sheet(item: $whatsNew, onDismiss: { WhatsNewGate.markSeen() }) { item in
                WhatsNewView(mode: item.mode)
            }
    }
}

/// Wraps the settings window with environment plumbing.
private struct SettingsRootView: View {
    var body: some View {
        SettingsView()
            .environment(ModelManager.shared)
            .environment(DocumentStore.shared)
            .environment(MeetingStore.shared)
            .environment(TemplateStore.shared)
            .environment(SpaceStore.shared)
            .environment(CalendarManager.shared)
    }
}
