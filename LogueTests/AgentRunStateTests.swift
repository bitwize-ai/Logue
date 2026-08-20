import Foundation
import Testing

@testable import Logue

/// The invariant issue #61 exists to establish, stated as tests: a run on one
/// surface can never paint an indicator onto the other's thread.
///
/// Every case here fails against a global flag — which is what
/// `AgentCoordinator.isProcessing` is today — so this suite is what stops the
/// scoping being quietly removed later.
@Suite("AgentRunState")
struct AgentRunStateTests {
    private let island = UUID()
    private let mainWindow = UUID()

    private func toolCall(_ name: String) -> AgentToolCall {
        AgentToolCall(toolName: name, arguments: "{}")
    }

    // MARK: - Idle

    @Test("A fresh state owns no conversation and shows nothing")
    func idleShowsNothing() {
        let state = AgentRunState()
        #expect(state.owns(island) == false)
        #expect(state.isProcessing(for: island) == false)
        #expect(state.isStreaming(for: island) == false)
        #expect(state.streamingText(for: island).isEmpty)
        #expect(state.activeToolCalls(for: island).isEmpty)
        #expect(state.lastError(for: island) == nil)
    }

    // MARK: - Scoping

    @Test("A run is visible to the conversation that started it")
    func runVisibleToOwner() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        #expect(state.isProcessing(for: island))
    }

    @Test("A run is invisible to every other conversation")
    func runInvisibleToOthers() {
        // The whole point: the island runs, the main window shows nothing.
        var state = AgentRunState()
        state.begin(conversationID: island)
        #expect(state.isProcessing(for: mainWindow) == false)
    }

    @Test("Streaming text does not leak to another conversation")
    func streamingTextDoesNotLeak() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.beginStreaming()
        state.appendToken("Hello")
        state.appendToken(" world")
        #expect(state.streamingText(for: island) == "Hello world")
        #expect(state.streamingText(for: mainWindow).isEmpty)
        #expect(state.isStreaming(for: mainWindow) == false)
    }

    @Test("Tool cards do not leak to another conversation")
    func toolCallsDoNotLeak() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.setActiveToolCalls([toolCall("web_search")])
        #expect(state.activeToolCalls(for: island).count == 1)
        #expect(state.activeToolCalls(for: mainWindow).isEmpty)
    }

    @Test("An error does not leak to another conversation")
    func errorDoesNotLeak() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.fail("Couldn't start the agent")
        #expect(state.lastError(for: island) == "Couldn't start the agent")
        #expect(state.lastError(for: mainWindow) == nil)
    }

    // MARK: - Lifecycle

    @Test("Finishing clears live state but keeps the error for its owner")
    func finishKeepsErrorForOwner() {
        // The banner has to outlive the run — the coordinator's own comment says it
        // stays set after isStreaming flips to false, until acknowledged.
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.beginStreaming()
        state.appendToken("partial")
        state.setActiveToolCalls([toolCall("web_search")])
        state.fail("Agent stream failed")
        state.finish()

        #expect(state.isProcessing(for: island) == false)
        #expect(state.isStreaming(for: island) == false)
        #expect(state.streamingText(for: island).isEmpty)
        #expect(state.activeToolCalls(for: island).isEmpty)
        #expect(state.lastError(for: island) == "Agent stream failed")
        // Still not the other surface's error.
        #expect(state.lastError(for: mainWindow) == nil)
    }

    @Test("Starting a new run clears the previous run's error")
    func beginClearsPreviousError() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.fail("Agent stream failed")
        state.finish()
        state.begin(conversationID: mainWindow)
        #expect(state.lastError(for: mainWindow) == nil)
    }

    @Test("A finished run's error does not follow ownership to the next conversation")
    func errorDoesNotFollowOwnership() {
        // Regression guard: keeping conversationID after finish must not mean the
        // next owner inherits the last owner's banner.
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.fail("island failure")
        state.finish()
        state.begin(conversationID: mainWindow)
        #expect(state.lastError(for: island) == nil)
        #expect(state.lastError(for: mainWindow) == nil)
    }

    @Test("Taking over mid-run hands live state to the new conversation only")
    func takeoverScopesToNewOwner() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.beginStreaming()
        state.appendToken("island tokens")
        state.begin(conversationID: mainWindow)

        #expect(state.isProcessing(for: mainWindow))
        #expect(state.isProcessing(for: island) == false)
        #expect(state.streamingText(for: island).isEmpty)
        #expect(state.streamingText(for: mainWindow).isEmpty)
    }

    @Test("Dismissing an error clears it")
    func dismissClearsError() {
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.fail("boom")
        state.dismissError()
        #expect(state.lastError(for: island) == nil)
    }

    @Test("Resetting streaming text between tool rounds keeps ownership")
    func resetStreamingTextKeepsOwnership() {
        // The coordinator clears streamingText between reasoning rounds; that must
        // not look like the run changing hands.
        var state = AgentRunState()
        state.begin(conversationID: island)
        state.beginStreaming()
        state.appendToken("round one")
        state.resetStreamingText()
        #expect(state.owns(island))
        #expect(state.isProcessing(for: island))
        #expect(state.streamingText(for: island).isEmpty)
    }

    // MARK: - Streaming stops more than once per run

    @Test("Ending streaming leaves the run processing")
    func endStreamingKeepsTheRunAlive() {
        // The graph stops streaming after every tool call and resumes; the run is still
        // going. If this cleared `isProcessing`, `send`'s `guard !isProcessing` would let a
        // second send start on top of the first, mid-run.
        var state = AgentRunState()
        let id = UUID()
        state.begin(conversationID: id)
        state.beginStreaming()
        state.appendToken("partial")

        state.endStreaming()

        #expect(state.isStreaming == false)
        #expect(state.isProcessing, "the run has not finished")
        #expect(state.owns(id))
        // The tokens so far are what the caller is about to commit as a message.
        #expect(state.streamingText == "partial")
    }

    @Test("A conversation that does not own the run still sees nothing mid-stream")
    func foreignConversationSeesIdleWhileStreaming() {
        var state = AgentRunState()
        let mine = UUID()
        let theirs = UUID()
        state.begin(conversationID: mine)
        state.beginStreaming()
        state.appendToken("hello")

        #expect(state.isStreaming(for: theirs) == false)
        #expect(state.streamingText(for: theirs).isEmpty)
        #expect(state.isProcessing(for: theirs) == false)
        // …while the owner sees all of it.
        #expect(state.isStreaming(for: mine))
        #expect(state.streamingText(for: mine) == "hello")
    }
}
