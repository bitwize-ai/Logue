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
            CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: true)
                == .dismiss
        )
    }

    @Test("The shortcut closes an island however much it is holding")
    func triggerDismissesRegardlessOfContent() {
        // The shortcut is deliberate, so it is not held to the bar a stray click is.
        // It is also the keyboard way out now that an island with a conversation
        // survives clicks and app switches.
        #expect(CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: true) == .dismiss)
    }

    @Test("The shortcut opens the chat island when nothing is up")
    func triggerPresentsWhenIdle() {
        #expect(
            CommandCenterChatRule.trigger(mode: nil, isShowingPanel: false)
                == .present
        )
    }

    @Test("The recording island gives way to the chat island")
    func triggerReplacesRecording() {
        let recording = CommandCenterMode.recording(meetingID: UUID())

        #expect(
            CommandCenterChatRule.trigger(mode: recording, isShowingPanel: true)
                == .replace
        )
    }

    @Test("A panel with no mode is replaced rather than left alone")
    func triggerReplacesWhenModeIsMissing() {
        #expect(
            CommandCenterChatRule.trigger(mode: nil, isShowingPanel: true)
                == .replace
        )
    }

    @Test("A stale mode with no panel still opens one")
    func triggerPresentsWhenModeOutlivesPanel() {
        // The mode is cleared after the close animation, so a trigger can arrive
        // while it still reads .chat with nothing on screen. Dismissing then would
        // be a shortcut that does nothing.
        #expect(
            CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: false)
                == .present
        )
    }

    // MARK: - Focus loss

    @Test("Switching apps closes an empty island")
    func focusLossDismissesEmptyChat() {
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: false) == .dismiss)
    }

    @Test("Switching apps leaves an island that holds something exactly as it is")
    func focusLossKeepsChatWithContent() {
        // This used to demote the panel to `.normal`, which read as "it closed": the
        // panel is non-activating, so clicking it never restored the level and the
        // island stayed buried under whatever the user had just clicked.
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: true) == .keep)
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
        #expect(CommandCenterChatContent(hasConversation: false, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasConversation: true, hasDraft: false).isEmpty)
        #expect(!CommandCenterChatContent(hasConversation: false, hasDraft: true).isEmpty)
        #expect(!CommandCenterChatContent(hasConversation: true, hasDraft: true).isEmpty)
    }

    @Test("A staged file makes an island non-empty")
    func stagedFilesCount() {
        // Attachments were the one kind of content the island could hold that nothing here
        // knew about, so an island holding a PDF and nothing else reported itself disposable
        // and was torn down by the next click or app switch.
        let staged = CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true)
        #expect(!staged.isEmpty)
    }

    @Test("A staged file survives an app switch")
    func stagedFilesSurviveFocusLoss() {
        // The rule reads `isEmpty`, so this follows from the case above — which is the point:
        // teaching the struct about attachments is what fixes every reader at once.
        let staged = CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true)
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !staged.isEmpty) == .keep)
    }

    @Test("An island with nothing staged is still disposable on an app switch")
    func emptyIslandStillGoesAway() {
        // The other direction, so the fix above cannot turn into "the island never closes".
        let empty = CommandCenterChatContent(hasConversation: false, hasDraft: false)
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !empty.isEmpty) == .dismiss)
    }

    @Test("A draft survives an app switch but not a deliberate dismissal")
    func draftIsProtectedFromFocusLossOnly() {
        let draftOnly = CommandCenterChatContent(hasConversation: false, hasDraft: true)

        // Switching apps is not a decision about the island, so it keeps the draft.
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !draftOnly.isEmpty) == .keep)

        // Clicking off it is such a decision, and has always discarded an unsent
        // prompt. Protecting the draft here would leave an island with no visible
        // way out — the close button only exists once there are messages.
        //
        // Staged files are the deliberate exception: a dropped file cannot be recovered
        // by retyping it, so `clickOff` checks `hasAttachments` while still ignoring
        // `hasDraft`. Esc remains the way out in both cases.
        #expect(!draftOnly.hasConversation)
        #expect(!draftOnly.hasAttachments)
    }

    @Test("A thread the island owns counts even before anything is drawn in it")
    func aConversationWithNoRowsIsStillContent() {
        // The bug this closes: `AgentCoordinator.send` appends the user message inside
        // a `Task`, while the composer clears synchronously. For a frame or two after
        // pressing Send there were no rows, no draft and no attachments — a completely
        // empty island by every rule here — so a click or an app switch in that window
        // destroyed a conversation that had just started.
        let justSent = CommandCenterChatContent(hasConversation: true, hasDraft: false)
        #expect(!justSent.isEmpty)
        #expect(!CommandCenterChatRule.clickOff(justSent))
        #expect(CommandCenterChatRule.focusLoss(mode: .chat, chatHasContent: !justSent.isEmpty) == .keep)
    }

    // MARK: - What a click that missed the island may close

    @Test("A click elsewhere closes an island holding nothing worth keeping")
    func clickOffClosesEmptyAndDraftOnly() {
        #expect(CommandCenterChatRule.clickOff(
            CommandCenterChatContent(hasConversation: false, hasDraft: false)
        ))
        // A draft is deliberately not protected: with no conversation there is no X,
        // so keeping the island here would leave it with no visible way out.
        #expect(CommandCenterChatRule.clickOff(
            CommandCenterChatContent(hasConversation: false, hasDraft: true)
        ))
    }

    @Test("A click elsewhere never closes an island holding a conversation or a file")
    func clickOffSparesConversationsAndAttachments() {
        #expect(!CommandCenterChatRule.clickOff(
            CommandCenterChatContent(hasConversation: true, hasDraft: false)
        ))
        // The inconsistency this fixes: the transparent-area click used to consult only
        // the conversation, so an island holding a staged PDF was torn down by a click
        // beside the pill while surviving one on another window.
        #expect(!CommandCenterChatRule.clickOff(
            CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true)
        ))
    }

    // MARK: - Esc

    @Test("Esc pressed in the island always closes it")
    func escapeInIslandAlwaysCloses() {
        // Deliberate: the user is looking at the island and asking for it to go away.
        for content in [
            CommandCenterChatContent(hasConversation: false, hasDraft: false),
            CommandCenterChatContent(hasConversation: false, hasDraft: true),
            CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true),
            CommandCenterChatContent(hasConversation: true, hasDraft: false),
        ] {
            #expect(CommandCenterChatRule.escape(content: content, pressedInIsland: true))
        }
    }

    @Test("Esc pressed in another app never closes a conversation")
    func escapeElsewhereSparesAConversation() {
        // The global monitor sees every Esc anywhere on the machine — closing a
        // dictation panel in another app should not throw away a thread here.
        #expect(!CommandCenterChatRule.escape(
            content: CommandCenterChatContent(hasConversation: true, hasDraft: false),
            pressedInIsland: false
        ))
        #expect(!CommandCenterChatRule.escape(
            content: CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true),
            pressedInIsland: false
        ))
    }

    @Test("Esc pressed in another app still closes an island holding nothing")
    func escapeElsewhereClosesEmpty() {
        // The other direction, so the fix cannot become "the island never closes".
        #expect(CommandCenterChatRule.escape(
            content: CommandCenterChatContent(hasConversation: false, hasDraft: false),
            pressedInIsland: false
        ))
    }

    @Test("Esc and a stray click agree about what may be closed")
    func escapeElsewhereMatchesClickOff() {
        // Two incidental inputs, one bar. Stated as an equivalence so a future edit
        // cannot make one of them stricter than the other without saying so here.
        for content in [
            CommandCenterChatContent(hasConversation: false, hasDraft: false),
            CommandCenterChatContent(hasConversation: false, hasDraft: true),
            CommandCenterChatContent(hasConversation: false, hasDraft: false, hasAttachments: true),
            CommandCenterChatContent(hasConversation: true, hasDraft: false),
            CommandCenterChatContent(hasConversation: true, hasDraft: true, hasAttachments: true),
        ] {
            #expect(
                CommandCenterChatRule.escape(content: content, pressedInIsland: false)
                    == CommandCenterChatRule.clickOff(content)
            )
        }
    }
}
