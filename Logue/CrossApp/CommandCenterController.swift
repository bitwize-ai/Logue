import Cocoa
import SwiftUI

extension Notification.Name {
    static let dismissCommandCenter = Notification.Name("dismissCommandCenter")
}

/// Panel mode for Command Center — chat or recording.
enum CommandCenterMode: Equatable {
    case chat
    case recording(meetingID: UUID)
}

/// Custom NSPanel subclass that can become key for text input.
class CommandCenterPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    /// Ensure the panel becomes key on any mouse interaction so buttons work
    /// even when Logue is not the active app.
    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}

/// NSHostingView subclass that renders with a fully transparent background.
/// Only clears the hosting view's own layer — never touches child views/layers
/// so SwiftUI's rendered content (capsules, fills, text) stays intact.
class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    /// Accept mouse clicks immediately, even when the panel is not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = .clear
    }
}

/// Transparent container view that passes clicks on empty area through.
/// The hosting view is pinned inside, so the area around it is empty.
/// Clicks on the empty area trigger `onClickEmptyArea`; clicks on
/// subviews pass straight through to SwiftUI via `hitTest`.
private class TransparentContainerView: NSView {
    override var isOpaque: Bool {
        false
    }

    /// Accept mouse clicks immediately, even when the panel is not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    var onClickEmptyArea: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        // Fully transparent — do not draw anything.
    }

    /// Route clicks: subview area → deepest child (SwiftUI buttons work),
    /// empty area → self (so `mouseDown` can fire `onClickEmptyArea`).
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point is in our superview's coordinate space.
        // Convert to our own coordinate space — this is the superview
        // coordinate space for each child, which is what hitTest expects.
        let localPoint: NSPoint = if let sv = superview {
            convert(point, from: sv)
        } else {
            point
        }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(localPoint) {
                return hit
            }
        }
        // No subview hit — return self only if we have an empty-area handler,
        // otherwise return nil to let the click pass through entirely.
        return onClickEmptyArea != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // Only called when hitTest returned self (empty area click).
        onClickEmptyArea?()
    }
}

/// Manages the Command Center panels — bottom-center chat island
/// and top-center recording island.
@MainActor
class CommandCenterController: ObservableObject {
    @Published var isVisible: Bool = false

    private var panel: CommandCenterPanel?
    private var currentMode: CommandCenterMode?
    private var escMonitor: Any?
    private var clickMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
    private var chatHasMessages: Bool = false

    /// The meeting ID of the active recording panel, used to restore the island.
    private(set) var activeRecordingMeetingID: UUID?
    /// Whether the panel was hidden because the Logue main window became active.
    private var hiddenForMainWindow: Bool = false
    private var appActiveObserver: NSObjectProtocol?
    private var appResignObserver: NSObjectProtocol?
    /// Suppresses the next app-became-active hide (used during panel creation).
    private var suppressNextActiveHide: Bool = false

    // MARK: - Public API

    func showChatPanel() {
        if panel != nil {
            dismissPanel()
        }
        currentMode = .chat
        chatHasMessages = false
        createPanel(mode: .chat)
    }

    func showRecordingPanel(meetingID: UUID) {
        hiddenForMainWindow = false
        if panel != nil {
            dismissPanel()
        }
        activeRecordingMeetingID = meetingID
        currentMode = .recording(meetingID: meetingID)
        createPanel(mode: .recording(meetingID: meetingID))
        setupAppActiveObservers()
    }

    /// Re-shows the recording island if a recording is still active and the panel is not visible.
    /// Works for recordings started from either the menu bar or the in-app UI.
    func restoreRecordingPanelIfNeeded() {
        guard RecordingSessionManager.shared.isRecording, panel == nil else { return }
        // Use stored ID if available, otherwise pick it up from the recorder
        let meetingID = activeRecordingMeetingID ?? RecordingSessionManager.shared.currentMeetingID
        guard let meetingID else { return }
        activeRecordingMeetingID = meetingID
        hiddenForMainWindow = false
        currentMode = .recording(meetingID: meetingID)
        createPanel(mode: .recording(meetingID: meetingID))
        setupAppActiveObservers()
    }

    // MARK: - App Active Visibility

    private func setupAppActiveObservers() {
        // Avoid duplicate observers
        tearDownAppActiveObservers()

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppBecameActive() }
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppResignedActive() }
        }
    }

    private func tearDownAppActiveObservers() {
        if let obs = appActiveObserver {
            NotificationCenter.default.removeObserver(obs); appActiveObserver = nil
        }
        if let obs = appResignObserver {
            NotificationCenter.default.removeObserver(obs); appResignObserver = nil
        }
    }

    private func handleAppBecameActive() {
        guard case .recording = currentMode else { return }
        // Skip if this activation was triggered by panel creation
        if suppressNextActiveHide {
            suppressNextActiveHide = false
            return
        }
        // Only hide when the main Logue window (not a panel) is the key window
        let mainWindowIsKey = NSApp.windows.contains { window in
            !(window is NSPanel) && window.isKeyWindow
        }
        guard mainWindowIsKey else { return }
        hiddenForMainWindow = true
        panel?.animator().alphaValue = 0
    }

    private func handleAppResignedActive() {
        guard RecordingSessionManager.shared.isRecording, activeRecordingMeetingID != nil else { return }
        if hiddenForMainWindow {
            hiddenForMainWindow = false
            if let panel {
                panel.animator().alphaValue = 1
                return
            }
        }
        // Panel was dismissed (minimized) or doesn't exist — recreate it
        if panel == nil {
            restoreRecordingPanelIfNeeded()
        }
    }

    // MARK: - Panel Creation

    // swiftlint:disable:next function_body_length
    private func createPanel(mode: CommandCenterMode) {
        let hostingView: NSView
        let panelWidth: CGFloat
        let panelHeight: CGFloat

        switch mode {
        case .chat:
            let chatView = CommandCenterChatView(
                onDismiss: { [weak self] in self?.dismissPanel() },
                onMessagesChanged: { [weak self] hasMessages in self?.chatHasMessages = hasMessages }
            )
            let hv = TransparentHostingView(rootView: chatView)
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = [.intrinsicContentSize]
            // Clip the hosting view's layer to match the pill's corner radius
            // so its default opaque background doesn't show as a dark rect.
            hv.wantsLayer = true
            hv.layer?.cornerRadius = AppThemeConstants.chatIslandCornerRadius
            hv.layer?.masksToBounds = true

            // Transparent container — the hosting view pins to the bottom
            // so it only occupies the height of its SwiftUI content.
            // The area above is fully transparent and passes clicks through.
            let container = TransparentContainerView()
            container.wantsLayer = true
            container.layer?.backgroundColor = .clear
            container.addSubview(hv)

            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hv.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            ])

            container.onClickEmptyArea = { [weak self] in
                guard let self, !self.chatHasMessages else { return }
                dismissPanel()
            }

            hostingView = container
            panelWidth = 740
            panelHeight = AppThemeConstants.chatIslandMaxHeight

        case let .recording(meetingID):
            let recordingView = CommandCenterRecordingView(
                recorder: RecordingSessionManager.shared,
                activeMeetingID: meetingID,
                onDismiss: { [weak self] in self?.dismissPanel() },
                onStop: { [weak self] in self?.dismissRecordingWithCollapse() },
                onOpenInApp: { [weak self] in self?.openMeetingInApp(meetingID) }
            )
            let hv = TransparentHostingView(rootView: recordingView)
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = [.intrinsicContentSize]
            hv.wantsLayer = true
            hv.layer?.cornerRadius = AppThemeConstants.recordingIslandCornerRadius
            hv.layer?.masksToBounds = true

            // Transparent container — hosting view pinned to the top so
            // content grows downward from the notch. Empty area below is transparent.
            let container = TransparentContainerView()
            container.wantsLayer = true
            container.layer?.backgroundColor = .clear
            container.addSubview(hv)

            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hv.topAnchor.constraint(equalTo: container.topAnchor),
                hv.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            ])

            hostingView = container
            panelWidth = AppThemeConstants.recordingIslandWidth
            panelHeight = AppThemeConstants.recordingIslandDefaultHeight
        }

        let panel = CommandCenterPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        if case .recording = mode {
            // Fixed width, resizable height only
            panel.minSize = NSSize(
                width: AppThemeConstants.recordingIslandWidth,
                height: AppThemeConstants.recordingIslandMinHeight
            )
            panel.maxSize = NSSize(
                width: AppThemeConstants.recordingIslandWidth,
                height: AppThemeConstants.recordingIslandMaxHeight
            )
        }

        positionPanel(panel, mode: mode)

        // Fade in
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        if case .recording = mode {
            // Suppress the app-active handler that would immediately hide the panel
            suppressNextActiveHide = true
        }
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        isVisible = true
        setupMonitors(mode: mode)
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel, mode: CommandCenterMode) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        switch mode {
        case .chat:
            let frame = screen.visibleFrame
            let x = frame.midX - panelWidth / 2
            let y = frame.minY + AppThemeConstants.chatIslandBottomMargin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        case .recording:
            // Use full screen frame to align with camera island at the very top.
            let fullFrame = screen.frame
            let x = fullFrame.midX - panelWidth / 2
            let y = fullFrame.maxY - panelHeight - AppThemeConstants.recordingIslandTopMargin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Monitors

    private func setupMonitors(mode: CommandCenterMode) {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.dismissPanel() }
            }
        }

        if case .chat = mode {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let clickLocation = event.locationInWindow
                let screenPoint = event.window?.convertPoint(toScreen: clickLocation) ?? clickLocation
                Task { @MainActor in
                    guard let self, let panel = self.panel else { return }
                    // Don't dismiss on outside click when there are messages
                    if self.chatHasMessages {
                        return
                    }
                    if !panel.frame.contains(screenPoint) {
                        self.dismissPanel()
                    }
                }
            }
        }

        dismissObserver = NotificationCenter.default.addObserver(
            forName: .dismissCommandCenter, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissPanel() }
        }
    }

    // MARK: - Dismiss

    /// Removes event monitors and notification observers used by the active panel.
    private func removeMonitors() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor); escMonitor = nil
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor); clickMonitor = nil
        }
        if let observer = dismissObserver {
            NotificationCenter.default.removeObserver(observer); dismissObserver = nil
        }
    }

    /// Shared cleanup after a panel closes. Resets panel state and optionally
    /// tears down recording observers if no recording is actively running.
    private func finalizeDismiss(preserveRecordingState: Bool = false) {
        panel = nil
        isVisible = false
        currentMode = nil
        chatHasMessages = false
        if !preserveRecordingState {
            activeRecordingMeetingID = nil
            tearDownAppActiveObservers()
        }
    }

    func dismissPanel() {
        removeMonitors()
        guard let panel else { return }

        // Keep recording state if a recording is still running (allows re-show from menu)
        let keepRecordingState = RecordingSessionManager.shared.isRecording && activeRecordingMeetingID != nil
        let isRecordingMode = if case .recording = currentMode {
            true
        } else {
            false
        }

        if isRecordingMode {
            // Scale-down + slide-up into the notch area (macOS native feel)
            let collapsedWidth = panel.frame.width * 0.6
            let collapsedHeight: CGFloat = 28
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                panel.animator().setFrame(
                    NSRect(
                        x: panel.frame.midX - collapsedWidth / 2,
                        y: panel.frame.maxY - collapsedHeight,
                        width: collapsedWidth,
                        height: collapsedHeight
                    ),
                    display: true
                )
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                panel.close()
                Task { @MainActor in self?.finalizeDismiss(preserveRecordingState: keepRecordingState) }
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                panel.close()
                Task { @MainActor in self?.finalizeDismiss(preserveRecordingState: keepRecordingState) }
            }
        }
    }

    /// Collapse the recording island upward into the notch area (Dynamic Island style),
    /// then show a brief "Meeting saved" toast.
    func dismissRecordingWithCollapse() {
        removeMonitors()

        // Clear recording state immediately to prevent re-show during animation
        activeRecordingMeetingID = nil
        hiddenForMainWindow = false
        tearDownAppActiveObservers()

        guard let panel else { return }

        let originalFrame = panel.frame
        let collapsedWidth: CGFloat = 120
        let collapsedHeight: CGFloat = 20

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            panel.animator().setFrame(
                NSRect(
                    x: originalFrame.midX - collapsedWidth / 2,
                    y: originalFrame.maxY - collapsedHeight,
                    width: collapsedWidth,
                    height: collapsedHeight
                ),
                display: true
            )
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.close()
            Task { @MainActor in
                self?.finalizeDismiss()
                self?.showSavedToast(near: originalFrame)
            }
        }
    }

    /// Show a brief "Meeting saved" toast centered near the top of the screen.
    private func showSavedToast(near frame: NSRect) {
        let toastView = RecordingSavedToastView()
        let hv = TransparentHostingView(rootView: toastView)

        let toastWidth: CGFloat = 180
        let toastHeight: CGFloat = 36

        let toastPanel = CommandCenterPanel(
            contentRect: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toastPanel.contentView = hv
        toastPanel.isOpaque = false
        toastPanel.backgroundColor = .clear
        toastPanel.level = .floating
        toastPanel.hasShadow = false
        toastPanel.hidesOnDeactivate = false
        toastPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hv.wantsLayer = true
        hv.layer?.cornerRadius = AppThemeConstants.radiusLarge
        hv.layer?.masksToBounds = true

        // Position: horizontally centered on screen, vertically where the island was
        let slideOffset: CGFloat = 12
        if let screen = NSScreen.main {
            let x = screen.frame.midX - toastWidth / 2
            let y = frame.maxY - toastHeight - AppThemeConstants.recordingIslandTopMargin - slideOffset
            toastPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Slide down + fade in
        toastPanel.alphaValue = 0
        toastPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            toastPanel.animator().alphaValue = 1
            var origin = toastPanel.frame.origin
            origin.y -= slideOffset
            toastPanel.animator().setFrameOrigin(origin)
        }

        // A21: Auto-dismiss with cancellable Task instead of DispatchQueue
        Task { [weak self] in
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            guard self != nil else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
                toastPanel.animator().alphaValue = 0
                var origin = toastPanel.frame.origin
                origin.y += slideOffset
                toastPanel.animator().setFrameOrigin(origin)
            } completionHandler: {
                toastPanel.close()
            }
        }
    }

    // MARK: - Helpers

    func openMeetingInApp(_ meetingID: UUID) {
        MeetingStore.shared.selectedMeetingID = meetingID
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
