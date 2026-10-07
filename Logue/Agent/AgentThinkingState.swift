import Foundation

/// Whether a surface should say it is working, rather than showing an answer.
///
/// There is a gap between a send and the first token — the model is loading, the context is
/// being built, the loop has not produced anything yet — and it is the moment a user is most
/// likely to conclude nothing happened and press the button again. The main window filled it
/// with a pulsing dot and a status line. The island filled it with a literal `"..."` rendered
/// as markdown, and before the assistant message existed at all it filled it with nothing.
///
/// *When* to show it was written out longhand at each place that needed it, and therefore
/// came out differently at each place. This is the one definition both surfaces ask.
///
/// Free of SwiftUI so the matrix is testable without a view.
enum AgentThinkingState {
    /// - Parameters:
    ///   - isProcessing: a run is in flight for this conversation.
    ///   - isStreaming: tokens are being delivered for this conversation.
    ///   - pendingAnswerText: what has arrived of the answer being produced *now*. Empty
    ///     while nothing has. Deliberately not "the last assistant message", which is the
    ///     previous answer and is non-empty for the whole of the next gap.
    ///   - hasActiveToolCard: a tool card is on screen saying what is happening — which
    ///     includes one waiting for approval, where the pause is the user's and a row claiming
    ///     the model is thinking would be untrue for as long as they take to answer. Two
    ///     things claiming to explain the same pause is worse than one.
    static func showsThinking(
        isProcessing: Bool,
        isStreaming: Bool,
        pendingAnswerText: String,
        hasActiveToolCard: @autoclosure () -> Bool
    ) -> Bool {
        guard isProcessing || isStreaming else { return false }
        guard pendingAnswerText.isEmpty else { return false }
        // Asked last, and only if it can still matter: answering it reads the conversation,
        // and this runs on every render while tokens stream.
        return !hasActiveToolCard()
    }

    /// Whether a tool card is already explaining the pause.
    ///
    /// A call waiting for approval counts — nothing is being thought about while the user
    /// decides — and so does one approved and still running, but only from the turn now in
    /// flight. See `AgentToolTimeline.unansweredInCurrentTurn` for the card a stopped run
    /// leaves behind.
    static func hasToolCard(activeToolCalls: [AgentToolCall], messages: [AgentMessage]) -> Bool {
        !activeToolCalls.isEmpty
            || !AgentToolTimeline.unansweredInCurrentTurn(in: messages).isEmpty
    }

    /// What the row says.
    ///
    /// One string, not a mapping from the running tool: the row is hidden whenever a tool
    /// card is showing, so it is never handed a tool to name. Stated here so both surfaces
    /// take the wording from the same place as the rule for showing it.
    static let label = UICopy.Status.thinking
}
