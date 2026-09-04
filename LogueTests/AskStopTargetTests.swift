import Foundation
import Testing

@testable import Logue

/// What the Stop button stops.
///
/// The decision used to live as a `private func` inside a `View`, so nothing could test it —
/// and its fallback branch reached into another surface's run.
@Suite("AskStopTarget")
struct AskStopTargetTests {
    @Test("Stop stops the research run this thread owns")
    func researchWins() {
        #expect(AskStopTarget.target(isResearchingHere: true, isAgentRunningHere: false) == .deepResearch)
    }

    @Test("Stop stops the agent run this thread owns")
    func agentLoopIsStopped() {
        #expect(AskStopTarget.target(isResearchingHere: false, isAgentRunningHere: true) == .agentLoop)
    }

    @Test("With nothing of ours running, Stop stops nothing")
    func idleStopsNothing() {
        // The bug this exists to prevent: the island's fallback called
        // AgentCoordinator.cancel() unconditionally, and that is unscoped — it kills the one
        // global task and rejects every pending approval. Pressing "New" on an idle island
        // stopped an answer streaming in the main window.
        #expect(AskStopTarget.target(isResearchingHere: false, isAgentRunningHere: false) == .nothing)
    }

    @Test("Research outranks the agent loop when both read as running")
    func researchOutranksTheLoop() {
        // It is the longer and more expensive of the two, so it is the one the user is
        // waiting on.
        #expect(AskStopTarget.target(isResearchingHere: true, isAgentRunningHere: true) == .deepResearch)
    }
}
