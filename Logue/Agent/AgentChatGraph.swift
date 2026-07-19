import Foundation
import LangGraph
import MLXLMCommon
import os.log

/// LangGraph-based agentic chat with native mlx-swift-lm tool calling,
/// checkpointing, loop detection, structured error handling, and an in-loop
/// user approval gate for destructive tools.
///
/// Graph topology:
/// ```
/// START → agent_reason ⟷ execute_tools → agent_reason (loop)
///              │
///              └─ (no tool calls / max rounds / loop detected) → END
/// ```
///
/// `execute_tools` inspects each pending call's `ToolClearance`. If approval is
/// required, it invokes `onApprovalRequired`, which the coordinator uses to surface
/// an in-chat Approve/Reject card (with Touch ID for `.dangerous`). Rejected /
/// timed-out calls aren't dispatched — a synthetic tool result is returned so the
/// model can reason about the refusal. Malformed tool arguments produce a structured
/// error feedback block (see `MalformedToolCall`) so the model can self-correct on
/// the next round.
actor AgentChatGraph {
    static let shared = AgentChatGraph()
    private init() {}

    private var _graph: StateGraph<AgentChatState>.CompiledGraph?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AgentChatGraph")

    /// Shared checkpoint saver for thread-based state persistence.
    let checkpointSaver = MemoryCheckpointSaver()

    // MARK: - Callbacks

    /// Callback for streaming individual tokens from agent_reason to the coordinator.
    /// Set by the coordinator before each graph run. Cleared after completion.
    var onReasoningToken: (@Sendable (String) -> Void)?

    /// Callback for when a tool call is detected during streaming.
    var onToolCallDetected: (@Sendable (ToolCall) -> Void)?

    /// Callback invoked when a tool requires user approval before execution.
    /// The coordinator posts an in-chat Approve/Reject card and awaits the user's decision.
    /// `clearance` lets the UI render the right variant (Touch ID for `.dangerous`).
    /// Returns `.approved` / `.rejected` / `.timedOut`.
    var onApprovalRequired: (@Sendable (_ toolCallID: UUID, _ toolName: String, _ argsJSON: String, _ clearance: ToolClearance) async -> ApprovalGate
        .Decision)?

    // MARK: - Public Interface

    /// Streams the agent graph execution with thread-based checkpointing.
    func stream(
        query: String,
        messages: [[String: any Sendable]],
        tools: [ToolSpec],
        threadId: String
    ) async throws -> AsyncThrowingStream<NodeOutput<AgentChatState>, Error> {
        let graph = try getOrBuildGraph()

        let inputs: [String: Any] = [
            "query": query,
            "tools": tools,
            "messages": messages,
            "round": 1,
            "has_tool_calls": false,
            "reasoning_text": "",
            "previous_reasoning": "",
            "error_message": "",
            "pending_tool_calls": [ToolCall](),
            "tool_retry_counts": [String: Int](),
        ]

        let config = RunnableConfig(threadId: threadId)
        logger.info("Starting agent graph (thread: \(threadId)) for: \(query.prefix(80), privacy: .public)")
        return try graph.stream(.args(inputs), config: config)
    }

    // MARK: - Graph Construction

    private func getOrBuildGraph() throws -> StateGraph<AgentChatState>.CompiledGraph {
        if let cached = _graph {
            return cached
        }
        let compiled = try buildGraph()
        _graph = compiled
        return compiled
    }

    // Complexity stems from the two graph nodes (agent_reason + execute_tools) that form a cohesive unit.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func buildGraph() throws -> StateGraph<AgentChatState>.CompiledGraph {
        let workflow = StateGraph(channels: AgentChatState.schema) { AgentChatState($0) }

        // Capture self weakly for node closures
        let graphActor = self

        // ── Node: agent_reason ────────────────────────────────────────────
        try workflow.addNode("agent_reason") { state in
            let messages = state.messages ?? []
            let tools = state.tools ?? []
            let round = state.round ?? 1

            let stream = await LLMEngine.shared.completeWithTools(
                messages: messages,
                tools: tools,
                temperature: 0.3,
                maxTokens: AppConstants.AgentDefaults.maxResponseTokens
            )

            var reasoningText = ""
            var toolCalls: [ToolCall] = []

            do {
                for try await generation in stream {
                    switch generation {
                    case let .chunk(text):
                        reasoningText += text
                        // Stream token to coordinator for real-time UI
                        await graphActor.onReasoningToken?(text)
                    case let .toolCall(call):
                        toolCalls.append(call)
                        await graphActor.onToolCallDetected?(call)
                    case .info:
                        break
                    }
                }
            } catch {
                let errorDesc = error.localizedDescription
                if reasoningText.isEmpty {
                    return [
                        "reasoning_text": "",
                        "has_tool_calls": false,
                        "pending_tool_calls": [ToolCall](),
                        "error_message": "LLM error: \(errorDesc)",
                        "round": round,
                    ]
                }
            }

            // Append assistant message to conversation history
            var updatedMessages = messages
            if !reasoningText.isEmpty || !toolCalls.isEmpty {
                var assistantMsg: [String: any Sendable] = ["role": "assistant"]
                if !reasoningText.isEmpty {
                    assistantMsg["content"] = reasoningText
                }
                updatedMessages.append(assistantMsg)
            }

            return [
                "reasoning_text": reasoningText,
                "previous_reasoning": state.reasoningText ?? "",
                "pending_tool_calls": toolCalls,
                "has_tool_calls": !toolCalls.isEmpty,
                "messages": updatedMessages,
                "round": round,
                "error_message": "",
            ]
        }

        // ── Node: execute_tools ───────────────────────────────────────────
        // Executes tool calls in parallel via withTaskGroup with per-tool timeout.
        // Tools that require confirmation are gated through `onApprovalRequired` first —
        // rejected/timed-out calls return a synthetic result instead of dispatching.
        try workflow.addNode("execute_tools") { state in
            let toolCalls = state.pendingToolCalls ?? []
            let round = (state.round ?? 1) + 1
            var messages = state.messages ?? []
            var retryCounts = state.toolRetryCounts ?? [:]
            let timeoutNanos = AppConstants.AgentDefaults.toolTimeoutSeconds * 1_000_000_000

            // Look up tool metadata (clearance) by name on the main actor.
            // When the user opted in to web search via the input bar's per-
            // message toggle, downgrade web tools to `.regular` so they
            // execute without a second Approve/Reject card — the toggle
            // itself was the consent. Without this, hitting "Search → send"
            // produces an approval card the user often doesn't realize they
            // need to click, and the search appears to "not work".
            let toolsMeta: [String: ToolClearance] = await MainActor.run {
                let oneShot = AgentCoordinator.shared.oneShotIncludeWebTools
                return Dictionary(
                    uniqueKeysWithValues: AgentCoordinator.shared.registeredTools.map { tool in
                        let isWebTool = tool.name == "web_search" || tool.name == "fetch_web_page"
                        let effective: ToolClearance = (oneShot && isWebTool) ? .regular : tool.clearance
                        return (tool.name, effective)
                    }
                )
            }

            // Separate calls that have exceeded retry limit
            var skippedResults: [[String: String]] = []
            var executableCalls: [(id: UUID, call: ToolCall)] = []
            for call in toolCalls {
                let toolName = call.function.name
                let currentRetries = retryCounts[toolName] ?? 0
                if currentRetries >= AppConstants.AgentDefaults.maxToolRetries {
                    skippedResults.append([
                        "tool": toolName,
                        "tool_call_id": UUID().uuidString,
                        "arguments": Self.formatArgs(call),
                        "output": "Skipped: max retries (\(AppConstants.AgentDefaults.maxToolRetries)) exceeded for \(toolName)",
                        "is_error": "true",
                    ])
                } else {
                    executableCalls.append((id: UUID(), call: call))
                }
            }

            // Execute tools in parallel with approval gate + per-tool timeout
            let executedResults: [(id: UUID, call: ToolCall, output: String, isError: Bool)] =
                await withTaskGroup(
                    of: (UUID, ToolCall, String, Bool).self,
                    returning: [(id: UUID, call: ToolCall, output: String, isError: Bool)].self
                ) { group in
                    for entry in executableCalls {
                        group.addTask {
                            let name = entry.call.function.name
                            let clearance = toolsMeta[name] ?? .regular

                            // Approval gate (sensitive + dangerous tools)
                            if clearance.requiresApproval {
                                let argsJSON = Self.formatArgs(entry.call)
                                let decision = await graphActor.onApprovalRequired?(
                                    entry.id, name, argsJSON, clearance
                                ) ?? .rejected

                                switch decision {
                                case .rejected:
                                    return (
                                        entry.id,
                                        entry.call,
                                        "The user declined this action. Do not retry without user consent.",
                                        true
                                    )
                                case .timedOut:
                                    return (
                                        entry.id,
                                        entry.call,
                                        "Approval request timed out. The action was not taken.",
                                        true
                                    )
                                case .approved:
                                    break
                                }
                            }

                            // Per-tool timeout guard
                            let result = await withTaskGroup(
                                of: (String, Bool)?.self,
                                returning: (String, Bool).self
                            ) { inner in
                                inner.addTask {
                                    await MLXToolDefinitions.dispatch(entry.call)
                                }
                                inner.addTask {
                                    try? await Task.sleep(nanoseconds: timeoutNanos)
                                    return nil
                                }
                                // First to complete wins
                                if let first = await inner.next(), let result = first {
                                    inner.cancelAll()
                                    return result
                                }
                                inner.cancelAll()
                                return ("Timeout: tool execution exceeded \(AppConstants.AgentDefaults.toolTimeoutSeconds)s", true)
                            }
                            return (entry.id, entry.call, result.0, result.1)
                        }
                    }
                    var collected: [(UUID, ToolCall, String, Bool)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }

            // Assemble results in original call order
            var results = skippedResults
            for entry in executableCalls {
                guard let executed = executedResults.first(where: { $0.id == entry.id })
                else { continue }

                let truncated = String(executed.output.prefix(AppConstants.AgentDefaults.toolResultMaxChars))
                let toolName = executed.call.function.name
                let argsJSON = Self.formatArgs(entry.call)

                let priorRetries = retryCounts[toolName] ?? 0
                if executed.isError {
                    retryCounts[toolName] = priorRetries + 1
                }

                // For UI/persistence, store the raw (truncated) error text — the card
                // shows the underlying error verbatim. The LLM sees the structured
                // feedback below.
                results.append([
                    "tool": toolName,
                    "tool_call_id": entry.id.uuidString,
                    "arguments": argsJSON,
                    "output": truncated,
                    "is_error": executed.isError ? "true" : "false",
                ])

                // Self-correcting feedback: when the tool fails, hand the model a
                // structured explanation (tool name, error, raw args, retry instruction)
                // so it can fix the call on the next round instead of repeating the
                // same mistake or giving up.
                let messageContent: String
                if executed.isError {
                    let malformed = MalformedToolCall(
                        toolName: toolName,
                        rawArguments: argsJSON,
                        errorDescription: truncated,
                        priorRetries: priorRetries
                    )
                    messageContent = malformed.getErrorFeedback()
                } else {
                    messageContent = truncated
                }
                messages.append([
                    "role": "tool",
                    "content": messageContent,
                    "name": toolName,
                ] as [String: any Sendable])
            }

            return [
                "tool_results": results,
                "messages": messages,
                "round": round,
                "pending_tool_calls": [ToolCall](),
                "has_tool_calls": false,
                "tool_retry_counts": retryCounts,
            ]
        }

        // ── Edges ─────────────────────────────────────────────────────────
        try workflow
            .addEdge(sourceId: START, targetId: "agent_reason")
            .addConditionalEdge(
                sourceId: "agent_reason",
                condition: { state -> String in
                    // Check for errors
                    let error = state.errorMessage ?? ""
                    if !error.isEmpty {
                        return "done"
                    }

                    let hasTools = state.hasToolCalls ?? false
                    let round = state.round ?? 1

                    // Max rounds reached
                    if round > AppConstants.AgentDefaults.maxToolRounds {
                        return "done"
                    }

                    // No tool calls → final answer
                    if !hasTools {
                        return "done"
                    }

                    // Loop detection: if reasoning is identical to previous round, stop
                    let current = state.reasoningText ?? ""
                    let previous = state.previousReasoning ?? ""
                    if !current.isEmpty, current == previous {
                        return "done"
                    }

                    return "has_tools"
                },
                edgeMapping: [
                    "has_tools": "execute_tools",
                    "done": END,
                ]
            )
            .addEdge(sourceId: "execute_tools", targetId: "agent_reason")

        // Compile with checkpoint support
        let config = CompileConfig(checkpointSaver: checkpointSaver)
        return try workflow.compile(config: config)
    }

    // MARK: - Helpers

    private static func formatArgs(_ call: ToolCall) -> String {
        let args = call.function.arguments.mapValues { $0.anyValue }
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }
}
