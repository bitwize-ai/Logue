import Foundation

/// What the Stop button stops.
///
/// Two coordinators can be behind one button and they do not know about each other, so the
/// decision has to be made somewhere — and it was made inside a `View`, where nothing could
/// test it. That is the same privacy-inside-a-view problem `AgentToolTimeline` was extracted
/// to fix, one button along.
///
/// The case that matters is `nothing`. The island's version fell back to cancelling the agent
/// loop unconditionally, and `AgentCoordinator.cancel()` is *unscoped* — it kills the single
/// global task and rejects every pending approval. So pressing "New" on an idle island
/// stopped an answer that was streaming in the main window.
enum AskStopTarget: Equatable {
    case deepResearch
    case agentLoop
    /// Nothing this surface owns is running, so Stop stops nothing. Cancelling "just in case"
    /// reaches into whatever the other surface is doing.
    case nothing

    /// - Parameters:
    ///   - isResearchingHere: a Deep Research run owned by *this* conversation.
    ///   - isAgentRunningHere: an agent-loop run owned by *this* conversation.
    static func target(isResearchingHere: Bool, isAgentRunningHere: Bool) -> AskStopTarget {
        // Deep Research first: it is the longer and more expensive of the two, and when both
        // somehow read as running it is the one the user is waiting on.
        if isResearchingHere {
            return .deepResearch
        }
        return isAgentRunningHere ? .agentLoop : .nothing
    }
}
