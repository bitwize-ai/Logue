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

    /// `Cmd+P` — open quick-open. A menu item rather than only an in-window key handler,
    /// because a main-menu key equivalent fires whatever holds focus inside the window,
    /// including the editor's text view.
    static let openQuickOpenPalette = Notification.Name("openQuickOpenPalette")

    /// Chat-first shortcuts.
    /// `Cmd+L` — start a new chat and surface Home. A conversation with no messages *is*
    /// the landing state, so this doubles as "go Home".
    static let chatNewConversation = Notification.Name("chatNewConversation")
    /// `Cmd+Shift+L` — surface Home and focus the input, leaving the thread intact.
    static let chatFocusInput = Notification.Name("chatFocusInput")
}

@main
struct LogueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Which panes the main window shows. Shared with `MainWindowView` through the same
    /// AppStorage key, which is also what persists the choice across launches.
    @AppStorage(AppConstants.UserDefaultsKeys.editorLayoutMode) private var layoutModeRaw =
        EditorLayoutMode.allPanels.rawValue

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

            CommandGroup(after: .newItem) {
                Button("Quick Open…") {
                    NotificationCenter.default.post(name: .openQuickOpenPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
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
                // Only `⌘+` is bound here, and a key equivalent of `+` matches nothing but
                // `⌘+` itself — measured, not assumed. On any layout where `+` needs Shift
                // that is a chord the user may never reach, so `⌘=` — the unshifted key in
                // the same physical position — is bound in `MainWindowView` instead. Not as
                // a second menu item, because SwiftUI allows one shortcut per button and a
                // second button would list "Zoom In" twice in the View menu.
                Button("Zoom In") { EditorZoom.mutatePersisted { $0.zoomIn() } }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { EditorZoom.mutatePersisted { $0.zoomOut() } }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { EditorZoom.mutatePersisted { $0.reset() } }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                // ⌘1 / ⌘2 / ⌘3. Each entry resolves its mode through
                // `EditorLayoutMode(shortcutNumber:)` rather than restating the pairing here,
                // so the menu cannot disagree with the model about which key means which layout.
                ForEach(1 ... EditorLayoutMode.allCases.count, id: \.self) { number in
                    if let mode = EditorLayoutMode(shortcutNumber: number),
                       let key = "\(number)".first
                    {
                        Button(mode.label) { layoutModeRaw = mode.rawValue }
                            .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                    }
                }

                Divider()
            }

            CommandGroup(replacing: .help) {
                Button(UICopy.WhatsNew.menuItem) { HelpMenuActions.showWhatsNew() }

                Divider()

                Button("Documentation") { HelpMenuActions.openDocumentation() }
                Button("Keyboard Shortcuts") { HelpMenuActions.openKeyboardShortcuts() }
                Button(UICopy.WhatsNew.chromeExtensionMenuItem) {
                    HelpMenuActions.openChromeExtension()
                }

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
                // The Help menu stays live while a sheet is up. Assigning here would swap
                // a multi-release catch-up deck for a single-release one mid-read, and
                // during onboarding AppKit would drop the sheet while leaving this set.
                guard hasCompletedOnboarding, whatsNew == nil else { return }
                whatsNew = WhatsNewSheetItem(mode: .askedForByName())
            }
            .environment(ModelManager.shared)
            .environment(DocumentStore.shared)
            .environment(MeetingStore.shared)
            .environment(SpaceStore.shared)
            .environment(RecordingSessionManager.shared)
            .environment(TemplateStore.shared)
            .environment(CalendarManager.shared)
            .task {
                // After the store has loaded and after SandboxContainerMigrator has run in init():
                // recovery reads files whose location that migration may just have changed.
                await RecordingSessionManager.shared.recoverInterruptedSessions()
            }
            .sheet(
                isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: {
                        if !$0 {
                            hasCompletedOnboarding = true
                        }
                    }
                ),
                // onDismiss is the only signal that the wizard's sheet is actually gone.
                // The flag flips before the dismissal, so anything keyed to it is guessing.
                onDismiss: { presentDiscoverTour() },
                content: {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .environment(ModelManager.shared)
                    .interactiveDismissDisabled()
                }
            )
            .task {
                // The tour belongs to a fresh install and waits for the wizard; only
                // release notes are owed to someone who has been here before.
                guard hasCompletedOnboarding else { return }
                if case let .whatsNew(releases) = WhatsNewGate.presentationForLaunch() {
                    whatsNew = WhatsNewSheetItem(mode: .whatsNew(releases))
                }
            }
            .sheet(item: $whatsNew) { item in WhatsNewView(mode: item.mode) }
    }

    /// Shows the first-run tour once the onboarding sheet has actually gone.
    ///
    /// `@MainActor` because only `body` inherits it from `View`; without it the `Task`
    /// would write the sheet's state off the main actor.
    @MainActor
    private func presentDiscoverTour() {
        Task {
            try? await Task.sleep(for: AppConstants.Delays.sheetHandoff)
            // The Help menu is reachable during the wait, so this must not overwrite a
            // sheet the user asked for themselves.
            guard whatsNew == nil else { return }
            whatsNew = WhatsNewSheetItem(mode: .discover)
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
