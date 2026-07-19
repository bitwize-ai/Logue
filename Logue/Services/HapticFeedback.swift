import AppKit

/// Thin wrapper around `NSHapticFeedbackManager` that standardizes which pattern
/// is appropriate for which user action. Safe to call on any hardware — the system
/// no-ops when Force Touch / haptic trackpad support isn't available or the user
/// has disabled "Force Click and haptic feedback" in System Settings.
///
/// Use sparingly — haptics should confirm success of a meaningful action, not
/// punctuate every button press.
enum HapticFeedback {
    /// Subtle tap. Use for routine positive confirmations (send message, copy).
    static func generic() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.generic, performanceTime: .now)
    }

    /// Alignment feedback. Use when the UI "snaps" into a new state
    /// (focus mode enter/exit, sidebar collapse, drag-snap).
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.alignment, performanceTime: .now)
    }

    /// Boundary-crossed feedback. Use for state transitions that matter
    /// (action item marked complete, bookmark added, threshold reached).
    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer
            .perform(.levelChange, performanceTime: .now)
    }

    // MARK: - Semantic shortcuts (Phase A0)

    //
    // These are the four chat-domain events that warrant a haptic. Keep this
    // list small — haptics get noisy fast.

    /// User pressed send on a chat message.
    static func send() {
        generic()
    }

    /// User stopped a generating response.
    static func stop() {
        levelChange()
    }

    /// User copied something (message, code block, snippet).
    static func copy() {
        generic()
    }

    /// User switched the active model.
    static func modelSwitch() {
        alignment()
    }
}
