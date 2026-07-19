import Foundation
import LangGraph
import MLXLMCommon

/// LangGraph state for the agentic chat pipeline with native tool calling.
///
/// Channels:
/// - `Channel<T>()` — overwrites on update
/// - `AppenderChannel<T>()` — appends to array on update
struct AgentChatState: AgentState {
    // MARK: - Schema

    static var schema: Channels = [
        // Input
        "query": Channel<String>(),
        "tools": Channel<[ToolSpec]>(),

        // Messages for LLM (built up across rounds)
        "messages": Channel<[[String: any Sendable]]>(),

        // Agent reasoning
        "reasoning_text": Channel<String>(),
        "pending_tool_calls": Channel<[ToolCall]>(),
        "has_tool_calls": Channel<Bool>(),

        // Tool execution (appends across rounds)
        "tool_results": AppenderChannel<[String: String]>(),

        // Control
        "round": Channel<Int>(),
        "previous_reasoning": Channel<String>(),
        "error_message": Channel<String>(),
        "tool_retry_counts": Channel<[String: Int]>(),
    ]

    // MARK: - Protocol

    var data: [String: Any]
    init(_ initState: [String: Any]) {
        data = initState
    }

    // MARK: - Typed Accessors

    var query: String? {
        value("query")
    }

    var tools: [ToolSpec]? {
        value("tools")
    }

    var messages: [[String: any Sendable]]? {
        value("messages")
    }

    var reasoningText: String? {
        value("reasoning_text")
    }

    var hasToolCalls: Bool? {
        value("has_tool_calls")
    }

    var round: Int? {
        value("round")
    }

    var toolResults: [[String: String]]? {
        value("tool_results")
    }

    var pendingToolCalls: [ToolCall]? {
        value("pending_tool_calls")
    }

    var previousReasoning: String? {
        value("previous_reasoning")
    }

    var errorMessage: String? {
        value("error_message")
    }

    var toolRetryCounts: [String: Int]? {
        value("tool_retry_counts")
    }
}
