import Foundation
import Testing

@testable import Logue

/// Pairing tool calls with their results, and settling what a card should show when the
/// stored status and the result disagree.
///
/// This was a `private func` inside the main window's message list, so none of it was
/// reachable from a test or from the island. Both of those are now false.
@Suite("AgentToolTimeline")
struct AgentToolTimelineTests {
    private func call(
        id: UUID = .init(),
        name: String = "search_web",
        status: AgentToolCallStatus = .completed
    ) -> AgentToolCall {
        AgentToolCall(id: id, toolName: name, arguments: "{}", status: status)
    }

    private func callMessage(_ calls: [AgentToolCall]) -> AgentMessage {
        AgentMessage(role: .toolCall, content: "", toolCalls: calls)
    }

    private func resultMessage(for id: UUID, output: String = "ok", isError: Bool = false) -> AgentMessage {
        AgentMessage(
            role: .toolResult,
            content: "",
            toolResult: AgentToolResult(toolCallID: id, output: output, isError: isError)
        )
    }

    // MARK: - Pairing

    @Test("A call is paired with the result carrying its id")
    func pairsOnIdentity() {
        let wanted = call()
        let other = call()
        let messages = [
            callMessage([wanted, other]),
            resultMessage(for: other.id, output: "other"),
            resultMessage(for: wanted.id, output: "mine"),
        ]
        #expect(AgentToolTimeline.result(for: wanted.id, in: messages)?.output == "mine")
    }

    @Test("A result stored before its call is still found")
    func orderingIsNotAssumed() {
        // Ordering is how the conversation happens to be built, not something the store
        // promises on read. Search only forwards from the call and a result that sorted
        // oddly renders as a call that never finished.
        let subject = call()
        let messages = [resultMessage(for: subject.id), callMessage([subject])]
        #expect(AgentToolTimeline.result(for: subject.id, in: messages) != nil)
    }

    @Test("A call with no result yet pairs with nothing")
    func unfinishedCallHasNoResult() {
        let subject = call(status: .running)
        #expect(AgentToolTimeline.result(for: subject.id, in: [callMessage([subject])]) == nil)
    }

    // MARK: - Display status

    @Test("A result outranks the stored status")
    func resultWinsOverStoredStatus() {
        // The case that produced it: the user approved the call on the other surface, so the
        // stored status is still `.needsConfirmation` while the tool has already run.
        let subject = call(status: .needsConfirmation)
        let result = AgentToolResult(toolCallID: subject.id, output: "done")
        #expect(AgentToolTimeline.displayStatus(of: subject, result: result) == .completed)
    }

    @Test("A failed result shows as failed, not completed")
    func errorResultShowsFailed() {
        let subject = call(status: .running)
        let result = AgentToolResult(toolCallID: subject.id, output: "boom", isError: true)
        #expect(AgentToolTimeline.displayStatus(of: subject, result: result) == .failed)
    }

    @Test("With no result the stored status stands")
    func storedStatusStandsWithoutAResult() {
        for status: AgentToolCallStatus in [.pending, .running, .needsConfirmation, .failed] {
            #expect(AgentToolTimeline.displayStatus(of: call(status: status), result: nil) == status)
        }
    }

    // MARK: - Awaiting approval

    @Test("A call that has already run is not awaiting approval")
    func answeredCallIsNotPending() {
        // The island's approval strip filtered on the stored status alone, so a call answered
        // in the main window kept its Approve and Deny buttons on the island — offering a
        // decision about something that had already happened.
        let subject = call(status: .needsConfirmation)
        let messages = [callMessage([subject]), resultMessage(for: subject.id)]
        #expect(AgentToolTimeline.awaitingApproval(in: messages).isEmpty)
    }

    @Test("A call still waiting is reported")
    func unansweredCallIsPending() {
        let subject = call(name: "delete_document", status: .needsConfirmation)
        let pending = AgentToolTimeline.awaitingApproval(in: [callMessage([subject])])
        #expect(pending.map(\.toolName) == ["delete_document"])
    }

    // MARK: - Entries

    @Test("Entries keep the order the calls were made in")
    func entriesAreOrdered() {
        let first = call(name: "read_document")
        let second = call(name: "search_web")
        let messages = [callMessage([first]), callMessage([second])]
        #expect(AgentToolTimeline.entries(in: messages).map(\.call.toolName) == ["read_document", "search_web"])
    }

    @Test("An entry carries the display status, not the stored one")
    func entryCarriesDisplayStatus() {
        let subject = call(status: .needsConfirmation)
        let messages = [callMessage([subject]), resultMessage(for: subject.id, isError: true)]
        let entry = AgentToolTimeline.entries(in: messages).first
        #expect(entry?.status == .failed)
        #expect(entry?.call.status == .failed, "the card reads the call, so it has to carry it too")
    }

    @Test("A conversation with no tool calls has no entries")
    func plainConversationHasNoEntries() {
        let messages = [
            AgentMessage(role: .user, content: "hello"),
            AgentMessage(role: .assistant, content: "hi"),
        ]
        #expect(AgentToolTimeline.entries(in: messages).isEmpty)
        #expect(AgentToolTimeline.awaitingApproval(in: messages).isEmpty)
    }
}
