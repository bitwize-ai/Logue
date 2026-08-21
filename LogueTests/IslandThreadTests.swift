import Foundation
import Testing

@testable import Logue

/// What the island draws for a conversation, and in what order.
///
/// The island dropped every tool turn on the floor, so a question that made the agent search
/// the web showed the answer and no sign of how it was reached. These cases pin what replaced
/// that, and the ordering in particular: a card is only useful sitting between the question
/// that caused it and the answer that used it.
@Suite("IslandThread")
struct IslandThreadTests {
    private func user(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, content: text)
    }

    private func assistant(_ text: String) -> AgentMessage {
        AgentMessage(role: .assistant, content: text)
    }

    private func toolCall(_ name: String, id: UUID = .init(), status: AgentToolCallStatus = .completed) -> AgentMessage {
        AgentMessage(
            role: .toolCall,
            content: "",
            toolCalls: [AgentToolCall(id: id, toolName: name, arguments: "{}", status: status)]
        )
    }

    private func toolResult(for id: UUID, isError: Bool = false) -> AgentMessage {
        AgentMessage(
            role: .toolResult,
            content: "out",
            toolResult: AgentToolResult(toolCallID: id, output: "out", isError: isError)
        )
    }

    private func kinds(_ rows: [IslandRow]) -> [String] {
        rows.map { row in
            switch row {
            case let .message(message): message.isUser ? "user" : "assistant"
            case let .tool(entry): "tool:\(entry.call.toolName)"
            }
        }
    }

    // MARK: - Ordering

    @Test("A tool card sits between the question and the answer")
    func toolCardIsInPlace() {
        let callID = UUID()
        let rows = IslandThread.rows(
            for: [
                user("what happened today"),
                toolCall("search_web", id: callID),
                toolResult(for: callID),
                assistant("Here is what I found."),
            ],
            isStreaming: false
        )
        #expect(kinds(rows) == ["user", "tool:search_web", "assistant"])
    }

    @Test("A tool result is never a row of its own")
    func resultIsNotARow() {
        // It is rendered inside the card for the call it answers. A row would show the raw
        // tool output as if the assistant had said it.
        let callID = UUID()
        let rows = IslandThread.rows(
            for: [toolCall("read_document", id: callID), toolResult(for: callID)],
            isStreaming: false
        )
        #expect(rows.count == 1)
    }

    @Test("A card carries its result once one has arrived")
    func cardCarriesItsResult() {
        let callID = UUID()
        let rows = IslandThread.rows(
            for: [toolCall("read_document", id: callID, status: .running), toolResult(for: callID)],
            isStreaming: false
        )
        guard case let .tool(entry) = rows.first else {
            Issue.record("expected a tool row")
            return
        }
        #expect(entry.result != nil)
        #expect(entry.status == .completed, "the result outranks the stored .running")
    }

    // MARK: - Empty assistant turns

    @Test("An assistant turn that only asked for tools draws no bubble")
    func emptyToolRequestingTurnIsDropped() {
        // The agent loop appends an assistant message carrying the tool calls and no prose.
        // Rendered, it is an empty grey bubble sitting above the card that explains it.
        let callID = UUID()
        let rows = IslandThread.rows(
            for: [
                user("summarise my notes"),
                assistant(""),
                toolCall("list_documents", id: callID),
                toolResult(for: callID),
                assistant("You have three."),
            ],
            isStreaming: false
        )
        #expect(kinds(rows) == ["user", "tool:list_documents", "assistant"])
    }

    @Test("The answer being written is kept even while it is empty")
    func streamingEmptyAnswerSurvives() {
        // It starts empty and fills in. Dropping it would make the island show nothing during
        // the gap before the first token, which reads as a send that did not happen.
        let rows = IslandThread.rows(for: [user("hi"), assistant("")], isStreaming: true)
        #expect(kinds(rows) == ["user", "assistant"])
    }

    // MARK: - Streaming

    @Test("Only the last assistant turn is marked as streaming")
    func onlyTheLastTurnStreams() {
        let rows = IslandThread.rows(
            for: [user("a"), assistant("first"), user("b"), assistant("second")],
            isStreaming: true
        )
        let streaming = rows.compactMap { row -> Bool? in
            if case let .message(message) = row, !message.isUser { return message.isStreaming }
            return nil
        }
        #expect(streaming == [false, true])
    }

    @Test("Nothing streams when no run is in flight")
    func nothingStreamsWhenIdle() {
        let rows = IslandThread.rows(for: [user("a"), assistant("done")], isStreaming: false)
        let streaming = rows.compactMap { row -> Bool? in
            if case let .message(message) = row, !message.isUser { return message.isStreaming }
            return nil
        }
        #expect(streaming == [false])
    }

    @Test("A trailing tool call does not make the previous answer stream")
    func aTrailingToolCallDoesNotStreamTheAnswer() {
        // `isStreaming` marks the last message, and the last message here is not the answer.
        let rows = IslandThread.rows(
            for: [user("a"), assistant("thinking about it"), toolCall("search_web")],
            isStreaming: true
        )
        let streaming = rows.compactMap { row -> Bool? in
            if case let .message(message) = row, !message.isUser { return message.isStreaming }
            return nil
        }
        #expect(streaming == [false])
    }

    // MARK: - Identity

    @Test("A row's id is the stored message's, so rows keep identity across a re-render")
    func rowIdentityIsStable() {
        let messages = [user("a"), assistant("b")]
        let first = IslandThread.rows(for: messages, isStreaming: false)
        let second = IslandThread.rows(for: messages, isStreaming: false)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.id) == messages.map(\.id))
    }

    @Test("An empty conversation has no rows")
    func emptyConversationHasNoRows() {
        #expect(IslandThread.rows(for: [], isStreaming: false).isEmpty)
    }
}
