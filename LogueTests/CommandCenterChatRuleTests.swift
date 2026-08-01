import Foundation
@testable import Logue
import Testing

/// The chat island's lifecycle rules — issue #46.
///
/// Reported as "the Ask Logue bar never closes, and sits over every other app".
/// These cover the two decisions that were wrong and are expressible without
/// AppKit: what the shortcut does to a showing island, and what losing frontmost
/// status means to one. The rest of the fix — panel identity through the close
/// animation, and monitor add/remove symmetry — lives in the controller and is
/// not reachable from here.
@Suite("Command Center chat rules")
struct CommandCenterChatRuleTests {
    // MARK: - Trigger

    @Test("The shortcut closes a chat island that is up in front")
    func triggerDismissesShowingChat() {
        #expect(
            CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: true, isChatBehindOtherApps: false)
                == .dismiss
        )
    }

    @Test("The shortcut brings back an island sent behind other apps")
    func triggerRaisesDemotedChat() {
        // Pressing the shortcut from another app is how you ask for the island
        // back. Dismissing it there would destroy an unsent prompt and show
        // nothing in its place — the reported symptom, reintroduced.
        #expect(
            CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: true, isChatBehindOtherApps: true)
                == .raise
        )
    }

    @Test("The shortcut opens the chat island when nothing is up")
    func triggerPresentsWhenIdle() {
        #expect(
            CommandCenterChatRule.trigger(mode: nil, isShowingPanel: false, isChatBehindOtherApps: false)
                == .present
        )
    }

    @Test("The recording island gives way to the chat island")
    func triggerReplacesRecording() {
        let recording = CommandCenterMode.recording(meetingID: UUID())

        #expect(
            CommandCenterChatRule.trigger(mode: recording, isShowingPanel: true, isChatBehindOtherApps: false)
                == .replace
        )
    }

    @Test("A panel with no mode is replaced rather than left alone")
    func triggerReplacesWhenModeIsMissing() {
        #expect(
            CommandCenterChatRule.trigger(mode: nil, isShowingPanel: true, isChatBehindOtherApps: false)
                == .replace
        )
    }

    @Test("A stale mode with no panel still opens one")
    func triggerPresentsWhenModeOutlivesPanel() {
        // The mode is cleared after the close animation, so a trigger can arrive
        // while it still reads .chat with nothing on screen. Dismissing then would
        // be a shortcut that does nothing.
        #expect(
            CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: false, isChatBehindOtherApps: false)
                == .present
        )
    }

    // MARK: - Focus loss

    @Test("Switching apps closes an empty island")
    func focusLossDismissesEmptyChat() {
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: false) == .dismiss)
    }

    @Test("Switching apps keeps what the island holds but stops it covering them")
    func focusLossDemotesChatWithContent() {
        // Content is a sent conversation or a prompt typed and not sent — the view
        // reports either, so switching apps mid-sentence cannot throw the draft away.
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: true) == .sendBehindOtherApps)
    }

    @Test("The recording island is left alone whatever the chat island holds")
    func focusLossIgnoresRecording() {
        let recording = CommandCenterMode.recording(meetingID: UUID())

        #expect(CommandCenterChatRule.focusLoss(mode: recording, chatHasContent: false) == nil)
        #expect(CommandCenterChatRule.focusLoss(mode: recording, chatHasContent: true) == nil)
    }

    @Test("Nothing showing means nothing to do")
    func focusLossIgnoresIdle() {
        #expect(CommandCenterChatRule.focusLoss(mode: nil, chatHasContent: false) == nil)
    }

    // MARK: - What the island is holding

    @Test("An island is empty only with neither a conversation nor a draft")
    func contentIsEmptyOnlyWhenBothAreAbsent() {
        #expect(CommandCenterChatContent(hasMessages: false, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: true, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: false, hasDraft: true).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: true, hasDraft: true).isEmpty)
    }

    @Test("A draft survives an app switch but not a deliberate dismissal")
    func draftIsProtectedFromFocusLossOnly() {
        let draftOnly = CommandCenterChatContent(hasMessages: false, hasDraft: true)

        // Switching apps is not a decision about the island, so it keeps the draft.
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !draftOnly.isEmpty)
            == .sendBehindOtherApps)

        // Clicking off it is such a decision, and has always discarded an unsent
        // prompt. Protecting the draft here would leave an island with no visible
        // way out — the close button only exists once there are messages.
        #expect(!draftOnly.hasMessages)
    }
}
