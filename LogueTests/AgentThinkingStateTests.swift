import Foundation
import Testing

@testable import Logue

/// When a surface should say it is working.
///
/// The gap between a send and the first token is the moment a user is most likely to decide
/// nothing happened and press the button again, and it was the gap the island did not fill.
@Suite("AgentThinkingState")
struct AgentThinkingStateTests {
    private func shows(
        processing: Bool = false,
        streaming: Bool = false,
        pending: String = "",
        toolCard: Bool = false
    ) -> Bool {
        AgentThinkingState.showsThinking(
            isProcessing: processing,
            isStreaming: streaming,
            pendingAnswerText: pending,
            hasActiveToolCard: toolCard
        )
    }

    @Test("The gap between a send and the first token is filled")
    func theGapIsFilled() {
        // Before any assistant message exists at all. The island showed nothing here.
        #expect(shows(processing: true))
        // And once it exists but is still empty.
        #expect(shows(processing: true, streaming: true, pending: ""))
    }

    @Test("It stops as soon as there is something to read")
    func stopsOnFirstToken() {
        #expect(shows(processing: true, streaming: true, pending: "The answer is") == false)
    }

    @Test("An idle conversation says nothing")
    func idleSaysNothing() {
        #expect(shows() == false)
        #expect(shows(pending: "an old answer") == false)
    }

    @Test("A tool card already explains the pause")
    func toolCardWins() {
        // Two things claiming to explain the same pause is worse than one — and the card is
        // the more specific of them, since it names the tool.
        #expect(shows(processing: true, toolCard: true) == false)
        #expect(shows(processing: true, streaming: true, pending: "", toolCard: true) == false)
    }

    @Test("Streaming alone is enough to be working")
    func streamingWithoutProcessingStillShows() {
        // Either flag means a run is in flight. Requiring `isProcessing` would leave the gap
        // blank on any path that raises the streaming flag first.
        #expect(shows(streaming: true))
        #expect(shows(streaming: true, toolCard: true) == false)
    }

    // MARK: - What counts as a tool card

    private func approvalCall() -> AgentMessage {
        AgentMessage(
            role: .toolCall,
            content: "",
            toolCalls: [AgentToolCall(toolName: "delete_document", arguments: "{}", status: .needsConfirmation)]
        )
    }

    @Test("A call waiting for approval is a card explaining the pause")
    func pendingApprovalCounts() {
        // The pause is the user's. "Thinking…" beside Approve would be untrue for as long
        // as they take to answer.
        let messages = [AgentMessage(role: .user, content: "delete it"), approvalCall()]
        #expect(AgentThinkingState.hasToolCard(activeToolCalls: [], messages: messages))
    }

    @Test("An approval abandoned in an earlier turn does not silence this one")
    func abandonedApprovalDoesNotCount() {
        // Stop a run while its card is up and the call stays unanswered for good. Counted,
        // it would hide the thinking row for every later send in the thread.
        let messages = [
            AgentMessage(role: .user, content: "delete it"),
            approvalCall(),
            AgentMessage(role: .user, content: "something else"),
        ]
        #expect(AgentThinkingState.hasToolCard(activeToolCalls: [], messages: messages) == false)
    }

    @Test("The conversation is not read once the answer has started")
    func toolCardIsNotAskedWhenItCannotMatter() {
        // Answering it walks the conversation, and this runs on every render while tokens
        // stream — so it is asked last, and only if nothing else has already said no.
        var asked = 0
        let card = { () -> Bool in
            asked += 1
            return false
        }
        _ = AgentThinkingState.showsThinking(
            isProcessing: true, isStreaming: true, pendingAnswerText: "The answer", hasActiveToolCard: card()
        )
        _ = AgentThinkingState.showsThinking(
            isProcessing: false, isStreaming: false, pendingAnswerText: "", hasActiveToolCard: card()
        )
        #expect(asked == 0)
        _ = AgentThinkingState.showsThinking(
            isProcessing: true, isStreaming: false, pendingAnswerText: "", hasActiveToolCard: card()
        )
        #expect(asked == 1)
    }

    @Test("A plain conversation has no tool card")
    func plainConversationHasNone() {
        let messages = [AgentMessage(role: .user, content: "hello")]
        #expect(AgentThinkingState.hasToolCard(activeToolCalls: [], messages: messages) == false)
    }
}
