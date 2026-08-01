import Foundation

/// What a Command Center trigger, or Logue losing frontmost status, means for the
/// chat island.
///
/// Kept free of AppKit so the matrix is testable without an NSPanel. The controller
/// owns the panel and only asks what to do with it — issue #46 was three separate
/// wrong answers to these questions, none of which a test could have reached while
/// they lived inside the window code.
enum CommandCenterChatRule {
    /// What pressing the Ask Logue shortcut should do.
    enum Trigger: Equatable {
        /// The chat island is already up — the shortcut puts it away.
        case dismiss
        /// Another island is up and has to go first.
        case replace
        /// Nothing is up.
        case present
    }

    /// What losing frontmost status should do to a chat island, or `nil` when the
    /// showing panel is not one.
    enum FocusLoss: Equatable {
        /// Nothing has been said to it, so nothing is lost by closing it.
        case dismiss
        /// It holds a conversation that only exists in the view's state. Keep it,
        /// but stop it covering the app being switched to.
        case sendBehindOtherApps
    }

    static func trigger(mode: CommandCenterMode?, isShowingPanel: Bool) -> Trigger {
        guard isShowingPanel else { return .present }
        if case .chat = mode { return .dismiss }
        return .replace
    }

    static func focusLoss(mode: CommandCenterMode?, chatHasMessages: Bool) -> FocusLoss? {
        guard case .chat = mode else { return nil }
        return chatHasMessages ? .sendBehindOtherApps : .dismiss
    }
}
