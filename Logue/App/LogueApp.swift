import SwiftUI

extension Notification.Name {
    static let openMeetingExportPanel = Notification.Name("openMeetingExportPanel")

    static let openSettingsGeneral = Notification.Name("openSettingsGeneral")
    static let openSettingsAboutAndCheckUpdates = Notification.Name("openSettingsAboutAndCheckUpdates")
    static let openKeyboardShortcutsWindow = Notification.Name("openKeyboardShortcutsWindow")
    static let openResourceUsageWindow = Notification.Name("openResourceUsageWindow")
    static let openReportBugWindow = Notification.Name("openReportBugWindow")

    /// Phase A: chat-first shortcuts.
    /// `Cmd+L` — start a new chat (and switch sidebar to Ask Logue).
    static let chatNewConversation = Notification.Name("chatNewConversation")
    /// `Cmd+Shift+L` — switch to Ask Logue and focus the input field.
    static let chatFocusInput = Notification.Name("chatFocusInput")
}

@main
struct LogueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

            CommandGroup(replacing: .help) {
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
}

// MARK: - Themed Root Views

/// Wraps the main window, injects all environments, follows system appearance.
private struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.openSettings) private var openSettings

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
