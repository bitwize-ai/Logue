import Foundation
@testable import Logue
import Testing

/// The chat island's lifecycle rules — issue #46.
///
/// Reported as "the Ask Logue bar never closes, and sits over every other app".
/// Each of the three causes has a test here: the shortcut rebuilt the island
/// instead of closing it, and losing frontmost status meant nothing at all to a
/// chat island, whether or not anything had been said to it.
@Suite("Command Center chat rules")
struct CommandCenterChatRuleTests {
    // MARK: - Trigger

    @Test("The shortcut closes a chat island that is already up")
    func triggerDismissesShowingChat() {
        #expect(CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: true) == .dismiss)
    }

    @Test("The shortcut opens the chat island when nothing is up")
    func triggerPresentsWhenIdle() {
        #expect(CommandCenterChatRule.trigger(mode: nil, isShowingPanel: false) == .present)
    }

    @Test("The recording island gives way to the chat island")
    func triggerReplacesRecording() {
        let recording = CommandCenterMode.recording(meetingID: UUID())

        #expect(CommandCenterChatRule.trigger(mode: recording, isShowingPanel: true) == .replace)
    }

    @Test("A stale mode with no panel still opens one")
    func triggerPresentsWhenModeOutlivesPanel() {
        // The mode is cleared after the close animation, so a trigger can arrive
        // while it still reads .chat with nothing on screen. Dismissing then would
        // be a shortcut that does nothing.
        #expect(CommandCenterChatRule.trigger(mode: .chat, isShowingPanel: false) == .present)
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

    @Test("The recording island is left alone")
    func focusLossIgnoresRecording() {
        let recording = CommandCenterMode.recording(meetingID: UUID())

        #expect(CommandCenterChatRule.focusLoss(mode: recording, chatHasContent: false) == nil)
    }

    @Test("Nothing showing means nothing to do")
    func focusLossIgnoresIdle() {
        #expect(CommandCenterChatRule.focusLoss(mode: nil, chatHasContent: false) == nil)
    }
}
