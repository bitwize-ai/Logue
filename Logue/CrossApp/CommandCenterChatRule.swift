import Foundation

/// What the chat island is currently holding.
///
/// The three are kept apart because they earn different protection. Deliberately
/// putting the island away — Esc pressed in it, the close button, the shortcut —
/// has always destroyed an unsent prompt, and a conversation is what a click off
/// the island must not throw away.
///
/// `hasConversation` is *not* "has visible messages". The island owns a thread the
/// moment `ensureConversation()` runs, which is before the first reply exists and
/// before `AgentCoordinator.send` appends anything — that append happens inside a
/// `Task`, while the composer clears synchronously. Asking about visible rows left
/// a window, a frame or two wide, in which a freshly-sent island reported itself
/// completely empty and every "an empty island is disposable" rule was armed
/// against it. Clicking Send could then close the island.
///
/// `hasAttachments` exists because staged files cost more to replace than typed
/// text does. A dropped file is not recoverable by retyping it: the user found it
/// in Finder, and after a dismissal they have to find it again. It was also the
/// one kind of content the island could hold that nothing here knew about, which
/// made an empty-looking island with a PDF staged on it disposable.
struct CommandCenterChatContent: Equatable {
    /// A thread exists — whether or not anything is drawn in it yet.
    var hasConversation: Bool
    var hasDraft: Bool
    var hasAttachments: Bool

    init(hasConversation: Bool, hasDraft: Bool, hasAttachments: Bool = false) {
        self.hasConversation = hasConversation
        self.hasDraft = hasDraft
        self.hasAttachments = hasAttachments
    }

    var isEmpty: Bool {
        !hasConversation && !hasDraft && !hasAttachments
    }
}

/// What a Command Center trigger, a click, an Esc, or Logue losing frontmost
/// status means for the chat island.
///
/// Kept free of AppKit so the matrix is testable without an NSPanel: the controller
/// owns the panel and only asks what to do with it. Issue #46 was several wrong
/// answers to these questions, none of which a test could reach while they lived
/// inside the window code.
///
/// The dividing line every rule here draws is **deliberate versus incidental**. The
/// close button, the shortcut, and Esc pressed inside the island are someone saying
/// "put this away" — they always work. Clicking another window, switching apps, or
/// pressing Esc in a different app are not about the island at all, and may only
/// close one that holds nothing worth keeping.
enum CommandCenterChatRule {
    /// What pressing the Ask Logue shortcut should do.
    enum Trigger: Equatable {
        /// The chat island is up — the shortcut puts it away. Deliberate, so it
        /// applies however much the island is holding.
        case dismiss
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
        /// It holds something. Leave it exactly as it is.
        ///
        /// This used to be `sendBehindOtherApps`, which dropped the panel to
        /// `.normal` level. That looked like a kindness and behaved like a
        /// disappearance: the panel is `.nonactivatingPanel`, so clicking it never
        /// re-activates Logue and never restored the level, leaving the island
        /// occluded by the window the user had just clicked with no way back except
        /// the shortcut. Users read that as "it closed".
        case keep
    }

    static func trigger(mode: CommandCenterMode?, isShowingPanel: Bool) -> Trigger {
        guard isShowingPanel else { return .present }
        if case .chat = mode {
            return .dismiss
        }
        return .replace
    }

    static func focusLoss(mode: CommandCenterMode?, chatHasContent: Bool) -> FocusLoss? {
        guard case .chat = mode else { return nil }
        return chatHasContent ? .keep : .dismiss
    }

    /// Whether a click that landed on some *other* window may close the island.
    ///
    /// A conversation or a staged file keeps it: neither is recoverable by the user
    /// retyping something, and an island holding a thread is the thing the close
    /// button exists for.
    ///
    /// A *draft* deliberately does not keep it. With no conversation there is no
    /// close button — it is only drawn above the transcript — so protecting a draft
    /// here would leave an island with no visible way out. Esc still closes it.
    static func clickOff(_ content: CommandCenterChatContent) -> Bool {
        !content.hasConversation && !content.hasAttachments
    }

    /// Whether Esc should close the island.
    ///
    /// - Parameter pressedInIsland: the keystroke went to the island itself. That is
    ///   someone deliberately dismissing what they are looking at, so it always
    ///   works. Esc pressed while another app is frontmost is not about the island,
    ///   and is held to the same bar as a stray click — which is why an island
    ///   holding a conversation survives it.
    static func escape(content: CommandCenterChatContent, pressedInIsland: Bool) -> Bool {
        pressedInIsland || clickOff(content)
    }
}
