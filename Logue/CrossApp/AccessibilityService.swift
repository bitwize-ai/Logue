import ApplicationServices
import Cocoa
import Foundation

/// Cross-app text detection and extraction using the macOS Accessibility API (AXUIElement).
@Observable
@MainActor
final class AccessibilityService {
    static let shared = AccessibilityService()

    var isAccessibilityGranted: Bool = false
    var focusedAppName: String = ""
    var focusedAppIcon: NSImage?
    var selectedText: String = ""
    var cursorPosition: CGPoint = .zero

    /// PID of the app that was focused before our panel appeared.
    private var sourceAppPID: pid_t?
    /// nonisolated(unsafe): Only set/read from @MainActor methods; needed because NSObjectProtocol
    /// is not Sendable but the observer is managed exclusively on the main thread.
    nonisolated(unsafe) private var appActivationObserver: NSObjectProtocol?
    /// nonisolated(unsafe): Same as appActivationObserver — managed exclusively on the main thread.
    nonisolated(unsafe) private var selfActivationObserver: NSObjectProtocol?

    private init() {
        checkAccessibilityPermission()
        startObservingAppActivation()
        startObservingSelfActivation()
    }

    deinit {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = selfActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - App Activation Observation

    private func startObservingAppActivation() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            Task { @MainActor [weak self] in
                self?.focusedAppName = app.localizedName ?? "Unknown"
                self?.focusedAppIcon = app.icon
            }
        }
    }

    // MARK: - Self Activation (recheck accessibility on app focus)

    private func startObservingSelfActivation() {
        selfActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
    }

    // MARK: - Permission

    @discardableResult
    func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = granted
        return granted
    }

    // MARK: - Source App Tracking

    func captureSourceApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            if frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                sourceAppPID = frontApp.processIdentifier
                focusedAppName = frontApp.localizedName ?? "Unknown"
                focusedAppIcon = frontApp.icon
            }
        }
    }

    private func getSourceAppElement() -> AXUIElement? {
        guard let pid = sourceAppPID else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    // MARK: - Focused Element

    /// Safely extracts an AXUIElement from an AnyObject returned by Accessibility APIs.
    /// Safely cast a CF value to AXUIElement after verifying its CFTypeID.
    /// Force cast is unavoidable for CF bridging — Swift has no `as?` for CF types (compiler warning: "always succeeds").
    /// CFGetTypeID verification provides the real type safety; the cast is just bridging syntax.
    private func asAXUIElement(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    /// Safely cast a CF value to AXValue after verifying its CFTypeID.
    private func asAXValue(_ value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXValue)
    }

    func getFocusedElement() -> AXUIElement? {
        if let appElement = getSourceAppElement() {
            var focusedElement: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
               let element = asAXUIElement(focusedElement)
            {
                return element
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = asAXUIElement(focusedApp)
        else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier {
            if let sourceApp = getSourceAppElement() {
                var focusedElement: AnyObject?
                if AXUIElementCopyAttributeValue(sourceApp, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
                   let element = asAXUIElement(focusedElement)
                {
                    return element
                }
            }
            return nil
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = asAXUIElement(focusedElement)
        else {
            return nil
        }
        return element
    }

    // MARK: - Get Selected Text

    func getSelectedText() -> String? {
        guard isAccessibilityGranted else {
            _ = checkAccessibilityPermission()
            return nil
        }
        guard let element = getFocusedElement() else { return nil }

        var selectedTextValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        guard result == .success, let text = selectedTextValue as? String, !text.isEmpty else {
            return getSelectedTextViaPasteboard()
        }

        selectedText = text
        return text
    }

    // MARK: - Get Full Text

    func getFullText() -> String? {
        guard let element = getFocusedElement() else { return nil }
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        return text
    }

    // MARK: - Replace Selected Text

    func replaceSelectedText(with newText: String) -> Bool {
        guard let element = getFocusedElement() else {
            replaceSelectedTextViaPasteboard(with: newText)
            return true
        }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
        if result == .success {
            return true
        }
        replaceSelectedTextViaPasteboard(with: newText)
        return true
    }

    // MARK: - Cursor Position

    func getCursorScreenPosition() -> CGPoint? {
        guard let element = getFocusedElement() else { return nil }

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }

        guard let rangeValue = selectedRange else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        ) == .success
        else { return nil }

        var rect = CGRect.zero
        guard let axValue = asAXValue(bounds),
              AXValueGetValue(axValue, .cgRect, &rect)
        else { return nil }
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            let convertedY = screenHeight - rect.maxY - 4
            let point = CGPoint(x: rect.midX, y: convertedY)
            cursorPosition = point
            return point
        }
        let point = CGPoint(x: rect.midX, y: rect.maxY + 4)
        cursorPosition = point
        return point
    }

    // MARK: - Focused App

    func updateFocusedAppName() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            if frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                focusedAppName = frontApp.localizedName ?? "Unknown"
                focusedAppIcon = frontApp.icon
            }
        }
    }

    // MARK: - Reactivate Source

    func reactivateSourceApp() {
        guard let pid = sourceAppPID else { return }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    // MARK: - Parameterized AX Queries (Inline Check)

    /// Returns the screen-space CGRect for a character range within the given element.
    /// AX returns top-left origin coords; this converts to AppKit bottom-left origin.
    func getBoundsForRange(_ range: NSRange, on element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var result: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        ) == .success
        else { return nil }

        var rect = CGRect.zero
        guard let axVal = asAXValue(result),
              AXValueGetValue(axVal, .cgRect, &rect)
        else { return nil }

        // Convert AX top-left origin to AppKit bottom-left origin.
        if let screen = NSScreen.main {
            rect.origin.y = screen.frame.height - rect.origin.y - rect.height
        }
        return rect
    }

    /// Returns the screen frame (position + size) of an accessibility element.
    func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard let pvAX = asAXValue(posValue),
              let svAX = asAXValue(sizeValue),
              AXValueGetValue(pvAX, .cgPoint, &position),
              AXValueGetValue(svAX, .cgSize, &size)
        else { return nil }

        var rect = CGRect(origin: position, size: size)
        // Convert AX top-left origin to AppKit bottom-left origin.
        if let screen = NSScreen.main {
            rect.origin.y = screen.frame.height - rect.origin.y - rect.height
        }
        return rect
    }

    /// Returns the currently visible character range for a text element.
    func getVisibleCharacterRange(of element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXVisibleCharacterRangeAttribute as CFString,
            &value
        ) == .success
        else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard let axVal = asAXValue(value),
              AXValueGetValue(axVal, .cfRange, &cfRange)
        else { return nil }

        return NSRange(location: cfRange.location, length: cfRange.length)
    }

    /// Returns the full text value of any accessibility element via kAXValueAttribute.
    func getFullText(from element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        return text
    }

    /// Replaces a text range in the target element by setting selection then replacing selected text.
    @discardableResult
    func replaceTextRange(_ range: NSRange, with replacement: String, in element: AXUIElement) -> Bool {
        // Set the selection to the target range.
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
        else { return false }

        // Replace the selected text.
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        ) == .success
    }

    // MARK: - Clipboard Fallback

    func getSelectedTextViaPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()

        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cmdUp?.flags = .maskCommand

        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        // Synchronous sleep required: CGEvent Cmd+C must complete before reading pasteboard.
        // Cannot use async Task.sleep because the entire copy-paste sequence is synchronous.
        // NOTE: This blocks the MainActor for 100ms — acceptable tradeoff for clipboard fallback.
        Thread.sleep(forTimeInterval: 0.1)

        let newText = pasteboard.string(forType: .string)

        // Sec-2: Always restore clipboard — clear if old content was nil
        if let old = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        } else {
            pasteboard.clearContents()
        }

        if let text = newText, !text.isEmpty {
            selectedText = text
            return text
        }
        return nil
    }

    /// Phase G: insert text at the source app's current caret position.
    /// Same clipboard-pivot mechanism as `replaceSelectedTextViaPasteboard`
    /// — when no text is selected, ⌘V drops the buffer at the caret;
    /// when selection exists, it replaces the selection. Used by the
    /// Inline Assistant's word-stepping mode (Tab / Shift+Tab).
    func insertTextAtCursor(_ text: String) {
        replaceSelectedTextViaPasteboard(with: text)
    }

    func replaceSelectedTextViaPasteboard(with newText: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        reactivateSourceApp()

        Task {
            try? await Task.sleep(for: AppConstants.Delays.accessibilityKeyEventYield)
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            cmdDown?.flags = .maskCommand
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            cmdUp?.flags = .maskCommand

            cmdDown?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)

            try? await Task.sleep(for: AppConstants.Delays.clipboardRestoreDelay)
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }
}
