import Foundation
import LangGraph
import MLXLMCommon

// MARK: - Approval flow

//
// Extracted from `AgentCoordinator` so the main type body stays under
// SwiftLint's `type_body_length` cap. Owns the user-facing approve/reject
// surface, the in-graph approval-request handler, and the helper that posts
// tool-call results back into the conversation.

extension AgentCoordinator {
    // MARK: - Approval API (called by UI)

    /// Approves a pending destructive tool call. Triggered by the Approve button in a
    /// `.needsConfirmation` tool card. For `.dangerous` clearance, the gate runs a
    /// Touch ID / device-owner check before resolving as approved.
    func approve(toolCallID: UUID, in conversationID: UUID) {
        // Resolve clearance + tool name from the existing card so the gate knows whether
        // to require biometric. Default to `.sensitive` if (somehow) the card isn't found
        // — never auto-elevate to dangerous, never auto-skip biometric.
        let store = AgentConversationStore.shared
        var clearance: ToolClearance = .sensitive
        var toolName = "unknown"
        if let conv = store.conversations.first(where: { $0.id == conversationID }) {
            outer: for message in conv.messages where message.role == .toolCall {
                for call in message.toolCalls where call.id == toolCallID {
                    clearance = call.clearance
                    toolName = call.toolName
                    break outer
                }
            }
        }
        updateApprovalCardStatus(toolCallID: toolCallID, in: conversationID, status: .running)
        Task {
            await ApprovalGate.shared.approve(
                toolCallID: toolCallID, clearance: clearance, toolName: toolName
            )
        }
    }

    /// Rejects a pending destructive tool call. Triggered by the Reject button in a
    /// `.needsConfirmation` tool card.
    func reject(toolCallID: UUID, in conversationID: UUID) {
        updateApprovalCardStatus(toolCallID: toolCallID, in: conversationID, status: .failed)
        Task { await ApprovalGate.shared.reject(toolCallID: toolCallID) }
    }

    /// Finds and updates the status of an existing toolCall card that's awaiting approval.
    func updateApprovalCardStatus(
        toolCallID: UUID,
        in conversationID: UUID,
        status: AgentToolCallStatus
    ) {
        let store = AgentConversationStore.shared
        guard let conv = store.conversations.first(where: { $0.id == conversationID }) else { return }
        for message in conv.messages where message.role == .toolCall {
            if message.toolCalls.contains(where: { $0.id == toolCallID }) {
                store.updateToolCallStatus(
                    in: conversationID,
                    messageID: message.id,
                    toolCallID: toolCallID,
                    status: status
                )
                return
            }
        }
    }

    // MARK: - Approval Handling

    /// Called by the graph when a tool that requires approval is about to execute.
    /// Posts an Approve/Reject card to the conversation (with Touch ID hint for
    /// `.dangerous`), then awaits the user's decision.
    func handleApprovalRequest(
        toolCallID: UUID,
        toolName: String,
        argsJSON: String,
        clearance: ToolClearance,
        conversationID: UUID
    ) async -> ApprovalGate.Decision {
        let store = AgentConversationStore.shared

        // Post the approval card
        let toolCall = AgentToolCall(
            id: toolCallID,
            toolName: toolName,
            arguments: argsJSON,
            status: .needsConfirmation,
            clearance: clearance
        )
        store.appendMessage(
            AgentMessage(role: .toolCall, content: "", toolCalls: [toolCall]),
            to: conversationID
        )

        // Await the user's decision (resolved by approve/reject methods, or timeout)
        return await ApprovalGate.shared.awaitDecision(toolCallID: toolCallID)
    }

    /// Posts a tool result to the conversation. If a card for this tool_call_id already
    /// exists (i.e. approval was required), just appends the result and updates the card's
    /// status. Otherwise creates a new card + result pair.
    func postToolResult(_ result: [String: String], in conversationID: UUID) {
        guard let toolName = result["tool"],
              let output = result["output"]
        else { return }

        let isError = result["is_error"] == "true"
        let argsJSON = result["arguments"] ?? "{}"
        let idString = result["tool_call_id"] ?? UUID().uuidString
        let toolCallID = UUID(uuidString: idString) ?? UUID()

        let store = AgentConversationStore.shared

        // Did an approval card already post for this call?
        let existingCard = store.conversations
            .first(where: { $0.id == conversationID })?
            .messages
            .first(where: { $0.role == .toolCall && $0.toolCalls.contains(where: { $0.id == toolCallID }) })

        if let existingCard {
            // Update status on the existing card
            store.updateToolCallStatus(
                in: conversationID,
                messageID: existingCard.id,
                toolCallID: toolCallID,
                status: isError ? .failed : .completed
            )
        } else {
            // Fresh (non-destructive) tool — post a new card
            let toolCall = AgentToolCall(
                id: toolCallID,
                toolName: toolName,
                arguments: argsJSON,
                status: isError ? .failed : .completed
            )
            store.appendMessage(
                AgentMessage(role: .toolCall, content: "", toolCalls: [toolCall]),
                to: conversationID
            )
        }

        // Append the result message (invisible in UI; read by findResult in ToolExecutionCard)
        let toolResult = AgentToolResult(toolCallID: toolCallID, output: output, isError: isError)
        store.appendMessage(
            AgentMessage(role: .toolResult, content: output, toolResult: toolResult),
            to: conversationID
        )
    }
}
