import Cocoa
import os.log
import SwiftUI

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

    /// Whether a click on the empty area is ours to act on. Consulted during hit
    /// testing, so it must answer without side effects. Answering `false` lets the
    /// click through to whatever is behind the panel — the panel is far taller
    /// than the pill drawn at the bottom of it, so claiming clicks we will not act
    /// on turns the transparent region into a dead zone that swallows them.
    var claimsEmptyAreaClicks: (() -> Bool)?

    /// The island's own drawn bounds, in this view's coordinates.
    ///
    /// "Empty area" used to mean "no SwiftUI subview claimed this point", which is
    /// not the same thing at all: the pill's background, its padding, and the gap
    /// between the transcript and the prompt bar are all inside the island and are
    /// claimed by nothing. Clicking any of them put the island away, which is the
    /// reported bug — a click *on* the island closing it.
    ///
    /// A click inside these bounds belongs to the island whether or not a control
    /// wanted it. Only clicks outside them are clicks off the island.
    var islandBounds: (() -> NSRect)?

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
        // Inside the island but claimed by no control — its background, its padding,
        // the gap between the transcript and the pill. That is still the island, so
        // take the click and do nothing with it rather than letting it fall through
        // to the app behind (which would activate that app and bury us).
        if isInsideIsland(localPoint) {
            return self
        }
        // Genuinely off the island: claim it only if we will act on it, otherwise
        // return nil to let the click pass through entirely.
        return claimsEmptyAreaClicks?() == true ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // Reached for two different clicks — one on the island's own inert area, one
        // beside it — and only the second is a decision about the island.
        let localPoint = convert(event.locationInWindow, from: nil)
        guard !isInsideIsland(localPoint) else {
            // Still hand it up the responder chain: `CommandCenterPanel.mouseDown`
            // makes the panel key, and swallowing this meant clicking the island's own
            // background no longer focused it — which silently disabled Esc, since the
            // local monitor only acts while the panel is key.
            super.mouseDown(with: event)
            return
        }
        onClickEmptyArea?()
    }

    private func isInsideIsland(_ localPoint: NSPoint) -> Bool {
        guard let islandBounds else { return false }
        return islandBounds().contains(localPoint)
    }
}

/// Manages the Command Center panels — bottom-center chat island
/// and top-center recording island.
@MainActor
class CommandCenterController: ObservableObject {
    @Published var isVisible: Bool = false

    /// Virtual key code for Escape.
    private static let escapeKeyCode: UInt16 = 53

    private var panel: CommandCenterPanel?
    private var currentMode: CommandCenterMode?
    private var escMonitor: Any?
    private var escLocalMonitor: Any?
    private var clickLocalMonitor: Any?
    private var chatContent = CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: false)

    /// The meeting ID of the active recording panel, used to restore the island.
    private(set) var activeRecordingMeetingID: UUID?
    /// Whether the panel was hidden because the Logue main window became active.
    private var hiddenForMainWindow: Bool = false
    private var appActiveObserver: NSObjectProtocol?
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "CommandCenter")
    private var appResignObserver: NSObjectProtocol?
    /// Suppresses the next app-became-active hide (used during panel creation).
    private var suppressNextActiveHide: Bool = false

    // MARK: - Public API

    /// Summons the chat island, or dismisses it when it is already up, so the
    /// activation shortcut is the same key that puts it away again.
    func toggleChatPanel() {
        switch CommandCenterChatRule.trigger(mode: currentMode, isShowingPanel: panel != nil) {
        case .dismiss:
            dismissPanel(reason: .hotkey)
            return
        case .replace:
            dismissPanel(reason: .replacedByRecording)
        case .present:
            break
        }
        currentMode = .chat
        chatContent = CommandCenterChatContent(hasConversation: false, hasDraft: false)
        createPanel(mode: .chat)
        setupAppActiveObservers()
    }

    func showRecordingPanel(meetingID: UUID) {
        hiddenForMainWindow = false
        if panel != nil {
            dismissPanel(reason: .replacedByRecording)
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
        // The chat island keeps its level for its whole life now, so there is
        // nothing to restore — it is simply left alone.
        if case .chat = currentMode {
            return
        }
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
        switch CommandCenterChatRule.focusLoss(mode: currentMode, chatHasContent: !chatContent.isEmpty) {
        case .dismiss:
            dismissPanel(reason: .focusLoss)
            return
        case .keep:
            return
        case nil:
            break
        }
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
                onDismiss: { [weak self] dismissal in
                    self?.dismissPanel(reason: dismissal == .openInLogue ? .openInLogue : .closeButton)
                },
                onContentChanged: { [weak self] content in self?.chatContent = content }
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

            // The same rule the click monitor uses, so an island holding a staged file
            // is not torn down by a click on the transparent area while surviving one
            // on another window.
            container.claimsEmptyAreaClicks = { [weak self] in
                guard let self else { return false }
                return CommandCenterChatRule.clickOff(chatContent)
            }
            // What counts as "on the island" — the hosting view is pinned to the bottom
            // and is only as tall as the SwiftUI content, so its frame is exactly the
            // island's drawn bounds.
            container.islandBounds = { [weak hv] in hv?.frame ?? .zero }
            container.onClickEmptyArea = { [weak self] in self?.dismissPanel(reason: .emptyAreaClick) }

            hostingView = container
            panelWidth = 740
            panelHeight = AppThemeConstants.chatIslandMaxHeight

        case let .recording(meetingID):
            let recordingView = CommandCenterRecordingView(
                recorder: RecordingSessionManager.shared,
                activeMeetingID: meetingID,
                onDismiss: { [weak self] in self?.dismissPanel(reason: .recordingDismissed) },
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
            if event.keyCode == Self.escapeKeyCode {
                // Global means the keystroke went to another app, so it is not a
                // decision about the island — held to the same bar as a stray click.
                Task { @MainActor in self?.dismissIfEscapeApplies(pressedInIsland: false) }
            }
        }

        // The local monitors below are chat-only on purpose. A global monitor never
        // sees events routed to our own app, and creating a panel makes it key, so
        // without them Esc and clicking away work only while some other app is
        // frontmost. The recording island is left with exactly the behaviour it had
        // rather than gaining an Esc that collapses it the instant recording starts.
        if case .chat = mode {
            escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == Self.escapeKeyCode, let self, panel?.isKeyWindow == true else { return event }
                // The island is key, so this is someone dismissing what they are
                // looking at. Always honoured, however much it holds.
                dismissIfEscapeApplies(pressedInIsland: true)
                return nil
            }

            // Deliberately no *global* mouse-down monitor. A mouse-down outside Logue is
            // another application being clicked, which is `handleAppResignedActive`'s
            // question, and it answers it with the real rule — an island holding something
            // goes behind rather than being destroyed.
            //
            // Watching it here as well duplicated that decision with a cruder one, and broke
            // dragging a file onto the island: the mouse-down that *starts* a drag in Finder
            // is outside the pill, and the pill is still empty because the drop has not
            // landed yet, so the island was torn down before the file arrived.

            clickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                // Reduced to two Sendable facts here rather than carrying the `NSWindow`
                // across the actor hop, which `NSWindow` is not.
                let clicked = event.window.map(ObjectIdentifier.init)
                let isPanel = event.window is NSPanel
                Task { @MainActor in
                    self?.dismissIfClickLandedElsewhere(windowID: clicked, isPanel: isPanel)
                }
                return event
            }
        }
    }

    /// Puts an empty chat island away when a click lands on one of Logue's *other*
    /// windows. What may be closed is `CommandCenterChatRule.clickOff`.
    ///
    /// Decided by window identity rather than by hit-testing a screen point against
    /// `panel.frame`, which is what this used to do and got wrong twice over. The
    /// point came from `event.locationInWindow` converted with the event's own
    /// window — and when that window was nil the code fell back to using
    /// *window-local* coordinates as though they were screen coordinates, so a click
    /// on the island itself could read as a click somewhere else and close it. The
    /// same test also counted clicks inside the attach picker as clicks elsewhere:
    /// `NSOpenPanel.begin` is non-modal and, because Logue is unsandboxed, runs in
    /// this process, so choosing a file tore down the very island it was for.
    ///
    /// Panels are excluded wholesale. Every panel Logue puts on screen — the picker,
    /// the toast, the island itself — is either ours or transient, and none of them
    /// is a user saying "I am done with the island".
    private func dismissIfClickLandedElsewhere(windowID: ObjectIdentifier?, isPanel: Bool) {
        guard case .chat = currentMode, let panel, let windowID, !isPanel else { return }
        guard windowID != ObjectIdentifier(panel) else { return }
        guard CommandCenterChatRule.clickOff(chatContent) else { return }
        dismissPanel(reason: .clickOnOtherWindow)
    }

    /// Handles Esc from either monitor. `pressedInIsland` is what separates a
    /// deliberate dismissal from a keystroke that happened elsewhere.
    private func dismissIfEscapeApplies(pressedInIsland: Bool) {
        // The global Esc monitor is installed for both modes, and `chatContent` is a chat
        // fact. Recording keeps the unconditional dismissal it has always had.
        guard case .chat = currentMode else {
            dismissPanel(reason: .escape(inIsland: pressedInIsland))
            return
        }
        guard panel != nil else { return }
        guard CommandCenterChatRule.escape(content: chatContent, pressedInIsland: pressedInIsland) else { return }
        dismissPanel(reason: .escape(inIsland: pressedInIsland))
    }

    // MARK: - Dismiss

    /// Removes the event monitors used by the active panel.
    private func removeMonitors() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor); escMonitor = nil
        }
        if let monitor = escLocalMonitor {
            NSEvent.removeMonitor(monitor); escLocalMonitor = nil
        }
        if let monitor = clickLocalMonitor {
            NSEvent.removeMonitor(monitor); clickLocalMonitor = nil
        }
    }

    /// Gives up ownership of the showing panel and hands it to the caller to
    /// animate away. Every piece of state describing it is cleared here, before
    /// returning — a dismissal takes 150–300ms to animate, and for that whole
    /// window anything reading `panel` or `currentMode` would otherwise be
    /// answered about a panel that is already leaving. That stale answer is what
    /// made the shortcut, a menu-bar click and the dismiss notification act on a
    /// dying panel instead of presenting a new one (issue #46).
    ///
    /// Returns `nil` when there is nothing showing.
    private func relinquishPanel() -> CommandCenterPanel? {
        guard let dismissed = panel else { return nil }

        // Keep recording state if a recording is still running (allows re-show from menu)
        let keepRecordingState = RecordingSessionManager.shared.isRecording && activeRecordingMeetingID != nil

        panel = nil
        isVisible = false
        currentMode = nil
        chatContent = CommandCenterChatContent(hasConversation: false, hasDraft: false)
        if !keepRecordingState {
            activeRecordingMeetingID = nil
            tearDownAppActiveObservers()
        }
        return dismissed
    }

    /// Why an island is being put away.
    ///
    /// Recorded on every dismissal because the island vanishing for the wrong reason
    /// is invisible after the fact — the panel is gone either way — and several paths
    /// can do it. With this, the log says which one fired.
    enum DismissReason: Equatable {
        /// The X in the island's header.
        case closeButton
        /// "Open in Logue" carried the thread to the main window.
        case openInLogue
        /// The Ask Logue shortcut, pressed while the island was up.
        case hotkey
        /// A recording island took its place.
        case replacedByRecording
        /// The recording island's own close button.
        case recordingDismissed
        /// Esc. `inIsland` is false when the keystroke went to another app.
        case escape(inIsland: Bool)
        /// A click landed on another Logue window.
        case clickOnOtherWindow
        /// A click landed on the panel's transparent area, around the island.
        case emptyAreaClick
        /// Logue stopped being frontmost and the island was empty.
        case focusLoss
    }

    func dismissPanel(reason: DismissReason) {
        Self.logger.notice("Command Center panel dismissed: \(String(describing: reason), privacy: .public)")
        removeMonitors()
        let isRecordingMode = if case .recording = currentMode {
            true
        } else {
            false
        }
        guard let panel = relinquishPanel() else { return }

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
            } completionHandler: {
                panel.close()
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.close()
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

        guard let panel = relinquishPanel() else { return }

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
            Task { @MainActor in self?.showSavedToast(near: originalFrame) }
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
