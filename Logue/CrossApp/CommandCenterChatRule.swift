import Foundation

/// What the chat island is currently holding.
///
/// The two are kept apart because they earn different protection. Deliberately
/// putting the island away — clicking off it, Esc, the close button, the shortcut
/// — has always destroyed an unsent prompt, and a conversation is what a click
/// off the island must not throw away. Switching apps is not a decision about the
/// island at all, so that leaves either alone.
struct CommandCenterChatContent: Equatable {
    var hasMessages: Bool
    var hasDraft: Bool

    var isEmpty: Bool {
        !hasMessages && !hasDraft
    }
}

/// What a Command Center trigger, or Logue losing frontmost status, means for the
/// chat island.
///
/// Kept free of AppKit so the matrix is testable without an NSPanel: the controller
/// owns the panel and only asks what to do with it. Issue #46 was several wrong
/// answers to these questions, none of which a test could reach while they lived
/// inside the window code.
enum CommandCenterChatRule {
    /// What pressing the Ask Logue shortcut should do.
    enum Trigger: Equatable {
        /// The chat island is up in front — the shortcut puts it away.
        case dismiss
        /// The island was sent behind other apps when Logue lost focus. The
        /// shortcut is how you ask for it back, so bring it forward rather than
        /// destroying it along with whatever was typed into it.
        case raise
        /// Another island is up and has to go first.
        case replace
        /// Nothing is up.
        case present
    }

    /// What losing frontmost status should do to a chat island, or `nil` when the
    /// showing panel is not one.
    enum FocusLoss: Equatable {
        /// Empty, so nothing is lost by closing it.
        case dismiss
        /// It holds a conversation, or a prompt typed but not sent, and both live
        /// only in the view's state. Keep it, but stop it covering the app being
        /// switched to.
        case sendBehindOtherApps
    }

    static func trigger(
        mode: CommandCenterMode?,
        isShowingPanel: Bool,
        isChatBehindOtherApps: Bool
    ) -> Trigger {
        guard isShowingPanel else { return .present }
        if case .chat = mode {
            return isChatBehindOtherApps ? .raise : .dismiss
        }
        return .replace
    }

    static func focusLoss(mode: CommandCenterMode?, chatHasContent: Bool) -> FocusLoss? {
        guard case .chat = mode else { return nil }
        return chatHasContent ? .sendBehindOtherApps : .dismiss
    }
}
