import Carbon
import Cocoa
import Foundation

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}

/// Global keyboard shortcut manager for system-wide activation.
@Observable
@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    var isShortcutActive: Bool = false
    var commandCenterShortcut: CustomShortcut

    private var eventMonitor: Any?
    private var localMonitor: Any?
    private var flagsEventMonitor: Any?
    private var flagsLocalMonitor: Any?
    private var lastShortcutTime: Date?
    private let debounceInterval: TimeInterval = 0.5

    /// Push-to-talk state: tracks whether Right Option is held down.
    private var isPushToTalkActive = false
    /// Timer for debouncing Right Option so regular Option+key combos aren't intercepted.
    private var pushToTalkTimer: Timer?
    private let pushToTalkDelay: TimeInterval = 0.3

    var onCommandCenterTriggered: (() -> Void)?
    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkStop: (() -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        let keys = AppConstants.UserDefaultsKeys.self

        if defaults.object(forKey: keys.shortcutCommandCenterKeyCode) != nil {
            commandCenterShortcut = CustomShortcut(
                keyCode: UInt16(defaults.integer(forKey: keys.shortcutCommandCenterKeyCode)),
                modifierFlags: UInt(defaults.integer(forKey: keys.shortcutCommandCenterModifiers))
            )
        } else {
            commandCenterShortcut = .defaultCommandCenter
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        flagsEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        isShortcutActive = true
    }

    func stopListening() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = flagsEventMonitor {
            NSEvent.removeMonitor(monitor)
            flagsEventMonitor = nil
        }
        if let monitor = flagsLocalMonitor {
            NSEvent.removeMonitor(monitor)
            flagsLocalMonitor = nil
        }
        pushToTalkTimer?.invalidate()
        pushToTalkTimer = nil
        isPushToTalkActive = false
        isShortcutActive = false
    }

    // MARK: - Shortcut Updates

    func updateCommandCenterShortcut(_ shortcut: CustomShortcut) {
        commandCenterShortcut = shortcut
        persistShortcuts()
    }

    func resetToDefaults() {
        commandCenterShortcut = .defaultCommandCenter
        persistShortcuts()
    }

    private func persistShortcuts() {
        let defaults = UserDefaults.standard
        let keys = AppConstants.UserDefaultsKeys.self

        defaults.set(Int(commandCenterShortcut.keyCode), forKey: keys.shortcutCommandCenterKeyCode)
        defaults.set(Int(commandCenterShortcut.modifierFlags), forKey: keys.shortcutCommandCenterModifiers)

        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    // MARK: - Key Handling

    private func handleKeyEvent(_ event: NSEvent) {
        if commandCenterShortcut.matches(event) {
            if let lastTime = lastShortcutTime, Date().timeIntervalSince(lastTime) < debounceInterval {
                return
            }
            lastShortcutTime = Date()
            onCommandCenterTriggered?()
        }

        // Any regular key press while Option is held cancels push-to-talk timer
        // (user is typing an Option+key combo like Option+G for ©, not holding to talk)
        if event.modifierFlags.contains(.option) {
            pushToTalkTimer?.invalidate()
            pushToTalkTimer = nil
        }
    }

    // MARK: - Push-to-Talk (Right Option Hold)

    private func handleFlagsChanged(_ event: NSEvent) {
        // Right Option key: keyCode 61
        guard event.keyCode == 61 else { return }

        let optionDown = event.modifierFlags.contains(.option)

        if optionDown, !isPushToTalkActive {
            // Start a debounce timer — only trigger after 300ms to avoid
            // interfering with quick Option+key character combos.
            pushToTalkTimer?.invalidate()
            pushToTalkTimer = Timer.scheduledTimer(withTimeInterval: pushToTalkDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPushToTalkActive = true
                    self.onPushToTalkStart?()
                }
            }
        } else if !optionDown {
            pushToTalkTimer?.invalidate()
            pushToTalkTimer = nil

            if isPushToTalkActive {
                isPushToTalkActive = false
                onPushToTalkStop?()
            }
        }
    }
}
