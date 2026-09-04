import Foundation

/// Whether a surface should say it is working, rather than showing an answer.
///
/// There is a gap between a send and the first token — the model is loading, the context is
/// being built, the loop has not produced anything yet — and it is the moment a user is most
/// likely to conclude nothing happened and press the button again. The main window filled it
/// with a pulsing dot and a status line. The island filled it with a literal `"..."` rendered
/// as markdown, and before the assistant message existed at all it filled it with nothing.
///
/// The wording already had one definition in `UICopy.Status.describe(toolName:)`. This is the
/// other half — *when* to show it — which was written out longhand at each place that needed
/// it, and therefore came out differently at each place.
///
/// Free of SwiftUI so the matrix is testable without a view.
enum AgentThinkingState {
    /// - Parameters:
    ///   - isProcessing: a run is in flight for this conversation.
    ///   - isStreaming: tokens are being delivered for this conversation.
    ///   - pendingAnswerText: what has arrived of the answer being produced *now*. Empty
    ///     while nothing has. Deliberately not "the last assistant message", which is the
    ///     previous answer and is non-empty for the whole of the next gap.
    ///   - hasActiveToolCard: a tool card is on screen saying what is happening. Two things
    ///     claiming to explain the same pause is worse than one.
    static func showsThinking(
        isProcessing: Bool,
        isStreaming: Bool,
        pendingAnswerText: String,
        hasActiveToolCard: Bool
    ) -> Bool {
        guard isProcessing || isStreaming else { return false }
        guard !hasActiveToolCard else { return false }
        return pendingAnswerText.isEmpty
    }

    /// What the row should say, given whatever the agent is doing.
    ///
    /// Delegates rather than restating: the strings are `UICopy`'s, and a second copy of the
    /// mapping is how one surface starts saying "Thinking…" while the other says "Searching
    /// the web…" about the same run.
    static func label(activeToolName: String?) -> String {
        UICopy.Status.describe(toolName: activeToolName)
    }
}
