import AppKit
import Foundation
import os.log

/// Implements all Troubleshooting menu actions.
@MainActor
enum TroubleshootingActions {
    // MARK: - Clear Cache and Quit

    static func clearCacheAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Clear Cache and Quit?"
        alert.informativeText = "Temporary files and cached data will be cleared. Your documents, meetings, and models will not be affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear and Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearCache()
        NSApp.terminate(nil)
    }

    // MARK: - Clear Cache and Restart

    static func clearCacheAndRestart() {
        let alert = NSAlert()
        alert.messageText = "Clear Cache and Restart?"
        alert.informativeText = "Temporary files and cached data will be cleared. " +
            "Your documents, meetings, and models will not be affected. The app will relaunch automatically."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear and Restart")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearCache()
        relaunch()
    }

    // MARK: - Reset Application Data

    static func resetApplicationData() {
        let alert = NSAlert()
        alert.messageText = "Reset All Application Data?"
        alert.informativeText = """
        This will permanently delete all your documents, meetings, spaces, \
        downloaded AI models, and cached data. The app will restart after reset.

        This action cannot be undone.

        Type "clear everything" below to enable the reset button:
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset Everything")
        alert.addButton(withTitle: "Cancel")

        guard let destructiveButton = alert.buttons.first else { return }
        destructiveButton.hasDestructiveAction = true
        destructiveButton.isEnabled = false

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 22))
        textField.placeholderString = "Type: clear everything"
        alert.accessoryView = textField

        let observer = ResetConfirmationObserver(button: destructiveButton, textField: textField)
        NotificationCenter.default.addObserver(
            observer,
            selector: #selector(ResetConfirmationObserver.textDidChange(_:)),
            name: NSTextField.textDidChangeNotification,
            object: textField
        )

        alert.window.initialFirstResponder = textField

        defer { NotificationCenter.default.removeObserver(observer) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DocumentStore.shared.clearAllData()
        MeetingStore.shared.clearAllData()
        SpaceStore.shared.clearAllData()

        let modelsDir = AppConstants.ModelStorage.rootDirectory
        do {
            try FileManager.default.removeItem(at: modelsDir)
        } catch {
            os_log(.error, "Failed to remove models directory: %{public}@", error.localizedDescription)
        }

        let preserve: Set<String> = [
            AppConstants.UserDefaultsKeys.hasCompletedOnboarding,
            AppConstants.UserDefaultsKeys.hasClearedSeedData,
        ]
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys
            .filter { !preserve.contains($0) }
            .forEach { defaults.removeObject(forKey: $0) }

        clearCache()
        relaunch()
    }

    // MARK: - Private helpers

    private static func clearCache() {
        let fm = FileManager.default

        // Only remove Logue-specific caches, not the entire temp directory.
        let logueCache = URL.cachesDirectory
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
        if fm.fileExists(atPath: logueCache.path) {
            do {
                try fm.removeItem(at: logueCache)
            } catch {
                os_log(.error, "Failed to remove cache directory: %{public}@", error.localizedDescription)
            }
        }

        let digestCache = URL.applicationSupportDirectory
            .appending(path: "Logue", directoryHint: .isDirectory)
            .appending(path: "daily_digest_cache.json")
        do {
            try fm.removeItem(at: digestCache)
        } catch {
            os_log(.error, "Failed to remove digest cache: %{public}@", error.localizedDescription)
        }
    }

    private static func relaunch() {
        guard let appURL = Bundle.main.bundleURL as URL? else {
            NSApp.terminate(nil)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
        // Give the new instance a moment to start before terminating.
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.relaunchTerminationInterval) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - ResetConfirmationObserver

private final class ResetConfirmationObserver: NSObject {
    private let button: NSButton
    private let textField: NSTextField

    init(button: NSButton, textField: NSTextField) {
        self.button = button
        self.textField = textField
    }

    @objc
    func textDidChange(_ notification: Notification) {
        button.isEnabled = textField.stringValue == "clear everything"
    }
}
