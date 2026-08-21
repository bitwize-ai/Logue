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

    @Test("The previous answer does not suppress the next gap")
    func previousAnswerIsNotThePendingOne() {
        // The bug this input shape avoids: reading "the last assistant message" instead of
        // the answer being produced now means the indicator never shows again after the
        // first reply, because that message is non-empty for the whole of every later gap.
        #expect(shows(processing: true, pending: ""))
    }

    @Test("The label follows what the agent is doing")
    func labelTracksTheTool() {
        #expect(AgentThinkingState.label(activeToolName: nil) == UICopy.Status.thinking)
        #expect(AgentThinkingState.label(activeToolName: "web_search") == UICopy.Status.searching)
        #expect(AgentThinkingState.label(activeToolName: "get_transcript") == UICopy.Status.reading)
    }
}
