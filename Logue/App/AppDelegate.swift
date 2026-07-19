import AppKit
import os.log
import Sparkle
import SwiftUI
import UserNotifications

// MARK: - Window Close Interceptor

/// Intercepts `windowShouldClose` to hide the window instead of destroying it,
/// forwarding all other NSWindowDelegate calls to SwiftUI's original delegate
/// via Objective-C message forwarding.
private class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    weak var originalDelegate: (any NSWindowDelegate)?
    var onClose: ((NSWindow) -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?(sender)
        return false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector != #selector(NSWindowDelegate.windowShouldClose(_:)),
           let original = originalDelegate as? NSObject,
           original.responds(to: aSelector)
        {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        if super.responds(to: aSelector) {
            return true
        }
        if let original = originalDelegate as? NSObject {
            return original.responds(to: aSelector)
        }
        return false
    }
}

// MARK: - Menu Bar Helpers

private extension NSImage {
    /// Small red dot used as a menu item icon to indicate active recording.
    static let menuBarRecordingDot: NSImage = {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

// MARK: - App Delegate

@MainActor
// swiftlint:disable:next type_body_length
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AppDelegate")

    // Singleton reference set in applicationDidFinishLaunching.
    // nonisolated(unsafe): written once on MainActor at launch, read-only thereafter.
    // swiftlint:disable:next modifier_order
    private(set) nonisolated(unsafe) weak static var shared: AppDelegate?

    /// Sparkle auto-updater controller — started on launch to handle background update checks.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    // Cross-app services
    private var commandCenterController: CommandCenterController?
    private var statusItem: NSStatusItem?
    private var shortcutsObserver: NSObjectProtocol?
    /// nonisolated(unsafe): set/cleared exclusively from MainActor.
    nonisolated(unsafe) private var inlineAssistantGlobalMonitor: Any?
    nonisolated(unsafe) private var inlineAssistantLocalMonitor: Any?

    /// Tracks whether recording was active on last menu rebuild, so we know when to start/stop the timer.
    private var wasRecordingOnLastRebuild: Bool = false
    /// Timer that rebuilds the menu every second while recording (for elapsed time updates).
    private var menuRefreshTimer: Timer?
    /// Low-frequency poller that detects recordings started from the in-app UI.
    private var recordingStatePoller: Timer?
    /// When true, `applicationDidBecomeActive` won't show the main window (e.g. when opening a floating panel).
    private var suppressMainWindowRestore = false

    // Dock visibility management
    private var windowCloseInterceptor: WindowCloseInterceptor?
    private var windowCloseObserver: NSObjectProtocol?
    private var mainWindowAttachObserver: NSObjectProtocol?
    private var keyboardShortcutsObserver: NSObjectProtocol?
    private weak var keyboardShortcutsWindow: NSWindow?
    private var resourceUsageObserver: NSObjectProtocol?
    private weak var resourceUsageWindow: NSWindow?
    private var bugReportObserver: NSObjectProtocol?
    private weak var bugReportWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        AppDelegate.shared = self
        logger.info("Logue launched.")
        ModelManager.shared.restoreActiveModelIfAvailable()

        // Set up notifications for action item reminders.
        UNUserNotificationCenter.current().delegate = self
        ReminderManager.shared.requestAuthorization()
        ReminderManager.shared.registerCategories()

        setupCrossAppServices()
        setupMenuBarItem()
        startRecordingStatePoller()
        setupWindowLifecycleObservers()

        shortcutsObserver = NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenuBarMenu() }
        }

        keyboardShortcutsObserver = NotificationCenter.default.addObserver(
            forName: .openKeyboardShortcutsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showKeyboardShortcutsWindow() }
        }

        resourceUsageObserver = NotificationCenter.default.addObserver(
            forName: .openResourceUsageWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showResourceUsageWindow() }
        }

        bugReportObserver = NotificationCenter.default.addObserver(
            forName: .openReportBugWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showBugReportWindow() }
        }

        // Start scheduled AI task scheduler.
        ScheduledTaskManager.shared.startScheduler()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification actions (Mark Complete, Snooze).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let itemIDString = userInfo["actionItemID"] as? String,
              let itemID = UUID(uuidString: itemIDString)
        else { return }

        switch response.actionIdentifier {
        case "MARK_COMPLETE":
            markActionItemComplete(itemID: itemID)

        case "SNOOZE_1H":
            snoozeReminder(itemID: itemID, bySeconds: 3600)

        default:
            break
        }
    }

    @MainActor
    private func markActionItemComplete(itemID: UUID) {
        let store = MeetingStore.shared
        for meeting in store.meetings where meeting.actionItems.contains(where: { $0.id == itemID }) {
            store.toggleActionItemCompleted(itemID: itemID, in: meeting.id)
            return
        }
    }

    @MainActor
    private func snoozeReminder(itemID: UUID, bySeconds: TimeInterval) {
        let store = MeetingStore.shared
        for meeting in store.meetings {
            if let item = meeting.actionItems.first(where: { $0.id == itemID }) {
                let snoozeDate = Date.now.addingTimeInterval(bySeconds)
                store.setActionItemReminder(
                    itemID: item.id,
                    in: meeting.id,
                    reminderDate: snoozeDate
                )
                return
            }
        }
    }

    // MARK: - App Lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Keep running for menu bar, command center, and global shortcuts.
        false
    }

    /// Called when the app becomes active (Spotlight launch, dock icon click, Finder open).
    /// Shows the main window if none are currently visible, unless a floating panel was intentionally opened.
    func applicationDidBecomeActive(_: Notification) {
        if suppressMainWindowRestore {
            suppressMainWindowRestore = false
            return
        }
        let hasVisibleWindows = NSApp.windows.contains { window in
            isMainAppWindow(window) && window.isVisible
        }
        if !hasVisibleWindows {
            showMainWindow()
        }
    }

    /// Backup handler for dock icon click (may not fire with WindowGroup — Apple bug FB9754295).
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_: Notification) {
        if let observer = shortcutsObserver {
            NotificationCenter.default.removeObserver(observer)
            shortcutsObserver = nil
        }
        if let observer = mainWindowAttachObserver {
            NotificationCenter.default.removeObserver(observer)
            mainWindowAttachObserver = nil
        }
        if let observer = keyboardShortcutsObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardShortcutsObserver = nil
        }
        if let observer = resourceUsageObserver {
            NotificationCenter.default.removeObserver(observer)
            resourceUsageObserver = nil
        }
        if let observer = bugReportObserver {
            NotificationCenter.default.removeObserver(observer)
            bugReportObserver = nil
        }
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }
        if let monitor = inlineAssistantGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            inlineAssistantGlobalMonitor = nil
        }
        if let monitor = inlineAssistantLocalMonitor {
            NSEvent.removeMonitor(monitor)
            inlineAssistantLocalMonitor = nil
        }
        MenuBarCompanionController.shared.uninstall()
        ResourceUsageMonitor.shared.stop()
        stopMenuRefreshTimer()
        recordingStatePoller?.invalidate()
        recordingStatePoller = nil
        ShortcutManager.shared.stopListening()
        ScheduledTaskManager.shared.stopScheduler()
        Task {
            await LLMEngine.shared.releaseSession()
        }
    }

    // MARK: - Dock Visibility

    /// Sets up observers to attach the close interceptor to the main window
    /// and track window lifecycle for dock icon visibility.
    private func setupWindowLifecycleObservers() {
        // Wait for the main SwiftUI window to appear, then attach close interceptor.
        mainWindowAttachObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let window = notification.object as? NSWindow,
                      self.isMainAppWindow(window),
                      self.windowCloseInterceptor == nil
                else { return }
                self.attachCloseInterceptor(to: window)
                if let observer = self.mainWindowAttachObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.mainWindowAttachObserver = nil
                }
            }
        }

        // Observe when non-intercepted windows close (e.g. Settings) to update dock visibility.
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.dockVisibilityUpdateInterval) { [weak self] in
                self?.updateDockVisibility()
            }
        }
    }

    /// Installs a delegate proxy on the main window that hides it instead of closing.
    private func attachCloseInterceptor(to window: NSWindow) {
        let interceptor = WindowCloseInterceptor()
        interceptor.originalDelegate = window.delegate
        interceptor.onClose = { [weak self] window in
            window.orderOut(nil)
            self?.updateDockVisibility()
        }
        window.delegate = interceptor
        windowCloseInterceptor = interceptor
        logger.debug("Window close interceptor attached to main window.")
    }

    // Window close observation handled by block-based windowCloseObserver

    /// Returns true for titled, normal-level windows that are not panels (i.e. main app windows).
    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) &&
            window.styleMask.contains(.titled) &&
            window.level == .normal
    }

    /// Shows or hides the dock icon based on whether any main windows are visible or minimized.
    private func updateDockVisibility() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            isMainAppWindow(window) &&
                (window.isVisible || window.isMiniaturized)
        }

        let target: NSApplication.ActivationPolicy = hasVisibleWindows ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
    }

    // MARK: - Cross-App Setup

    private func setupCrossAppServices() {
        let commandCenter = CommandCenterController()
        commandCenterController = commandCenter

        // Global shortcuts
        let shortcut = ShortcutManager.shared
        shortcut.onCommandCenterTriggered = { [weak self] in
            self?.showChatInterface()
        }
        shortcut.onPushToTalkStart = {
            Task { @MainActor in
                VoicePushToTalkManager.shared.startListening()
            }
        }
        shortcut.onPushToTalkStop = {
            Task { @MainActor in
                VoicePushToTalkManager.shared.stopListening()
            }
        }
        shortcut.startListening()

        // Phase D: ⌘⌃I → inline writing assistant. Bound here as a local
        // event tap so it works while Logue is in the background — the
        // ShortcutManager's existing AX-driven monitor catches keydowns
        // app-wide.
        installInlineAssistantHotkey()

        // Phase A0: ⌥Space → menu-bar companion floating window.
        MenuBarCompanionController.shared.install()

        logger.info("Cross-app services initialized.")
    }

    // MARK: - Inline Writing Assistant Hotkey

    /// Registers global + local NSEvent monitors for ⌘⌃I (keyCode 34 = "I").
    /// Global monitor fires when any other app is frontmost; local monitor
    /// catches the shortcut when Logue itself is active. Returns `nil` so the
    /// key event is consumed and doesn't propagate when Logue handles it.
    private func installInlineAssistantHotkey() {
        let mask: NSEvent.ModifierFlags = [.command, .control]

        inlineAssistantGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 34,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask
            else { return }
            Task { @MainActor in InlineAssistantController.shared.toggle() }
        }

        inlineAssistantLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 34,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask
            else { return event }
            Task { @MainActor in InlineAssistantController.shared.toggle() }
            return nil
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            } else {
                // Fallback to SF Symbol
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Logue")
                button.image?.size = NSSize(width: 18, height: 18)
            }
        }

        rebuildMenuBarMenu()
    }

    // swiftlint:disable:next function_body_length
    private func rebuildMenuBarMenu() {
        let menu = NSMenu()
        let recorder = RecordingSessionManager.shared
        let isRecording = recorder.isRecording

        let openItem = NSMenuItem(title: "Open Logue", action: #selector(showMainWindow), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        if isRecording {
            // Active recording indicator
            let meetingTitle: String = {
                if let meetingID = recorder.currentMeetingID,
                   let meeting = MeetingStore.shared.meetings.first(where: { $0.id == meetingID })
                {
                    return meeting.title
                }
                return "Meeting"
            }()
            let elapsed = TranscriptSegment.formatTime(recorder.elapsedTime)
            let recordingItem = NSMenuItem(
                title: "Recording: \(meetingTitle) — \(elapsed)",
                action: #selector(showActiveRecording),
                keyEquivalent: ""
            )
            recordingItem.target = self
            recordingItem.image = NSImage.menuBarRecordingDot
            menu.addItem(recordingItem)

            let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopActiveRecording), keyEquivalent: "")
            stopItem.target = self
            stopItem.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
            menu.addItem(stopItem)

            menu.addItem(NSMenuItem.separator())
        }

        let chatItem = NSMenuItem(title: "Ask Logue", action: #selector(showChatInterface), keyEquivalent: "")
        chatItem.target = self
        chatItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(chatItem)

        let onlineItem = NSMenuItem(title: "Online Meeting", action: #selector(startOnlineMeeting), keyEquivalent: "")
        onlineItem.target = self
        onlineItem.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
        onlineItem.isEnabled = !isRecording
        menu.addItem(onlineItem)

        let inPersonItem = NSMenuItem(title: "In-Person Meeting", action: #selector(startInPersonMeeting), keyEquivalent: "")
        inPersonItem.target = self
        inPersonItem.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)
        inPersonItem.isEnabled = !isRecording
        menu.addItem(inPersonItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Logue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Start/stop the refresh timer based on recording state
        if isRecording, !wasRecordingOnLastRebuild {
            startMenuRefreshTimer()
        } else if !isRecording, wasRecordingOnLastRebuild {
            stopMenuRefreshTimer()
        }
        wasRecordingOnLastRebuild = isRecording
    }

    private func startMenuRefreshTimer() {
        stopMenuRefreshTimer()
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenuBarMenu() }
        }
    }

    private func stopMenuRefreshTimer() {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    /// Polls recording state to detect changes from the in-app UI (start or stop).
    private func startRecordingStatePoller() {
        recordingStatePoller?.invalidate()
        recordingStatePoller = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let isRecording = RecordingSessionManager.shared.isRecording
                if isRecording != self.wasRecordingOnLastRebuild {
                    // Recording stopped from in-app UI — dismiss the floating island
                    if !isRecording {
                        self.commandCenterController?.dismissRecordingWithCollapse()
                    }
                    self.rebuildMenuBarMenu()
                }
            }
        }
    }

    // MARK: - Menu Actions

    /// Ensures the dock icon is visible and the app is frontmost, then runs the given closure.
    private func activateApp(then action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            try? await Task.sleep(for: AppConstants.Delays.appActivationYield)
            NSApp.activate(ignoringOtherApps: true)
            action()
        }
    }

    @objc
    private func showMainWindow() {
        activateApp {
            if let window = NSApp.windows.first(where: { self.isMainAppWindow($0) }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    @objc
    private func showSettings() {
        activateApp {
            NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
        }
    }

    private func showResourceUsageWindow() {
        if let existing = resourceUsageWindow {
            existing.makeKeyAndOrderFront(NSApp)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: ResourceUsageView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Resource Usage"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        NSApp.activate(ignoringOtherApps: true)
        resourceUsageWindow = window
    }

    private func showBugReportWindow() {
        if let existing = bugReportWindow {
            existing.makeKeyAndOrderFront(NSApp)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: BugReportView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Report Bug / Issue"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        NSApp.activate(ignoringOtherApps: true)
        bugReportWindow = window
    }

    private func showKeyboardShortcutsWindow() {
        // Reuse an existing window if already open.
        if let existing = keyboardShortcutsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: KeyboardShortcutsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Keyboard Shortcuts"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        NSApp.activate(ignoringOtherApps: true)
        keyboardShortcutsWindow = window
    }

    @objc
    private func showChatInterface() {
        suppressMainWindowRestore = true
        commandCenterController?.showChatPanel()
    }

    @objc
    private func showActiveRecording() {
        suppressMainWindowRestore = true
        commandCenterController?.restoreRecordingPanelIfNeeded()
    }

    @objc
    private func stopActiveRecording() {
        Task {
            await RecordingSessionManager.shared.stopRecording()
            commandCenterController?.dismissRecordingWithCollapse()
            rebuildMenuBarMenu()
        }
    }

    @objc
    private func startOnlineMeeting() {
        startMeeting(mode: .onlineMeeting)
    }

    @objc
    private func startInPersonMeeting() {
        startMeeting(mode: .inPerson)
    }

    private func startMeeting(mode: RecordingMode) {
        let store = MeetingStore.shared
        let meeting = store.createMeeting(
            title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            mode: mode,
            template: .general
        )
        store.selectedMeetingID = meeting.id

        Task {
            await RecordingSessionManager.shared.startRecording(for: meeting)
            rebuildMenuBarMenu()
        }

        commandCenterController?.showRecordingPanel(meetingID: meeting.id)
    }
}
