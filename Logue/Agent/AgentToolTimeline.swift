import Foundation

/// What the agent did during a turn, paired up and ready to render.
///
/// A tool call and its result are two separate messages in the conversation, linked only by
/// an id — the call is appended when the model asks for it, the result arrives whenever the
/// tool finishes. Rendering a card therefore means walking forward from a call looking for
/// the message that answers it.
///
/// That walk lived in a `private func findResult` inside `AgentChatView+Messages`, along with
/// the rule for what status to *show* when the stored status and the result disagree. Being
/// private to a view is why the island could not show tool history at all: the island runs
/// the same agent loop and stores the same messages, and the only thing it lacked was a way
/// to read them back. #61's rule is that a feature is mounted by both surfaces rather than
/// written twice, so the pairing moved here and both surfaces ask it.
///
/// Free of SwiftUI, so the pairing is testable without a view.
enum AgentToolTimeline {
    /// One tool call with whatever is known about how it went.
    struct Entry: Identifiable, Equatable {
        let call: AgentToolCall
        let result: AgentToolResult?
        /// What the card should show, which is not always `call.status` — see
        /// `displayStatus(of:result:)`.
        let status: AgentToolCallStatus

        var id: UUID {
            call.id
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.call.id == rhs.call.id
                && lhs.status == rhs.status
                && lhs.result?.output == rhs.result?.output
                && lhs.result?.isError == rhs.result?.isError
        }
    }

    /// The result answering `toolCallID`, if one has arrived.
    ///
    /// Every message is searched rather than only those after the call. Ordering is how the
    /// conversation is built, not something the store guarantees on read, and a result that
    /// sorted oddly would otherwise render as a call that never finished.
    static func result(for toolCallID: UUID, in messages: [AgentMessage]) -> AgentToolResult? {
        for message in messages where message.role == .toolResult {
            if let result = message.toolResult, result.toolCallID == toolCallID {
                return result
            }
        }
        return nil
    }

    /// What to show when the stored status and the result disagree.
    ///
    /// A call can be persisted as `.needsConfirmation` and still have a result: the user
    /// answered the prompt on the other surface, or the run was resumed. The result is the
    /// later fact, so it wins — otherwise a finished call keeps rendering Approve/Deny
    /// buttons for something that has already happened, which is worse on the island than
    /// anywhere else because the island is where the answer was given.
    static func displayStatus(
        of call: AgentToolCall,
        result: AgentToolResult?
    ) -> AgentToolCallStatus {
        guard let result else { return call.status }
        return result.isError ? .failed : .completed
    }

    /// The calls carried by `message`, each paired with its result.
    static func entries(
        in message: AgentMessage,
        allMessages: [AgentMessage]
    ) -> [Entry] {
        message.toolCalls.map { call in
            let result = result(for: call.id, in: allMessages)
            return Entry(
                call: AgentToolCall(
                    id: call.id,
                    toolName: call.toolName,
                    arguments: call.arguments,
                    status: displayStatus(of: call, result: result),
                    clearance: call.clearance
                ),
                result: result,
                status: displayStatus(of: call, result: result)
            )
        }
    }

    /// Every tool call in the conversation, in order, paired with its result.
    ///
    /// Used by the island, which renders tool history as its own rows rather than hanging
    /// cards off the message that carried them.
    static func entries(in messages: [AgentMessage]) -> [Entry] {
        messages.flatMap { entries(in: $0, allMessages: messages) }
    }

    /// The calls still waiting on the user.
    ///
    /// A call whose result has arrived is never pending however it was stored, which is the
    /// same disagreement `displayStatus` settles — stated once here so the approval strip and
    /// the history cards cannot answer it differently.
    static func awaitingApproval(in messages: [AgentMessage]) -> [AgentToolCall] {
        entries(in: messages)
            .filter { $0.status == .needsConfirmation }
            .map(\.call)
    }
}
