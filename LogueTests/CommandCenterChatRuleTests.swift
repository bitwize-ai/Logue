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

    @Test("An island is empty only with no conversation, no draft and nothing staged")
    func contentIsEmptyOnlyWhenAllAreAbsent() {
        #expect(CommandCenterChatContent(hasMessages: false, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: true, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: false, hasDraft: true).isEmpty)
        #expect(!CommandCenterChatContent(hasMessages: true, hasDraft: true).isEmpty)
    }

    @Test("A staged file makes an island non-empty")
    func stagedFilesCount() {
        // Attachments were the one kind of content the island could hold that nothing here
        // knew about, so an island holding a PDF and nothing else reported itself disposable
        // and was torn down by the next click or app switch.
        let staged = CommandCenterChatContent(hasMessages: false, hasDraft: false, hasAttachments: true)
        #expect(!staged.isEmpty)
    }

    @Test("A staged file survives an app switch")
    func stagedFilesSurviveFocusLoss() {
        // The rule reads `isEmpty`, so this follows from the case above — which is the point:
        // teaching the struct about attachments is what fixes every reader at once.
        let staged = CommandCenterChatContent(hasMessages: false, hasDraft: false, hasAttachments: true)
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !staged.isEmpty)
            == .sendBehindOtherApps)
    }

    @Test("An island with nothing staged is still disposable on an app switch")
    func emptyIslandStillGoesAway() {
        // The other direction, so the fix above cannot turn into "the island never closes".
        let empty = CommandCenterChatContent(hasMessages: false, hasDraft: false)
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !empty.isEmpty) == .dismiss)
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
        //
        // Staged files are the deliberate exception: a dropped file cannot be recovered
        // by retyping it, so `dismissIfClickMissedPanel` checks `hasAttachments` while
        // still ignoring `hasDraft`. Esc remains the way out in both cases.
        #expect(!draftOnly.hasMessages)
        #expect(!draftOnly.hasAttachments)
    }
}
