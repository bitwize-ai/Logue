import Foundation
import MLXLMCommon
import os.log

// MARK: - ToolClearance

/// Permission tier governing how the agent gates a tool before execution.
///
/// - `.regular`: read-only / pure-AI tools that don't mutate user data. No prompt.
/// - `.sensitive`: mutates content but reversible (creates, updates, renames, calendar
///   events, file exports). Surfaces an in-chat Approve/Reject card.
/// - `.dangerous`: irreversible destructive actions (deletes). Same in-chat card, but
///   tapping Approve triggers a Touch ID / device-owner biometric check before the call
///   is dispatched.
enum ToolClearance: String, Codable {
    case regular
    case sensitive
    case dangerous

    /// `true` when the tool needs a user-facing approval gate at all (sensitive or dangerous).
    var requiresApproval: Bool {
        self != .regular
    }

    /// `true` when approval requires biometric / device-owner re-auth.
    var requiresBiometric: Bool {
        self == .dangerous
    }
}

// MARK: - AgentTool Protocol

/// Protocol for tools that the agentic chat coordinator can invoke.
///
/// Each tool owns its JSON schema (via `spec`) so schema + implementation stay co-located.
/// `clearance` declares the permission tier — see `ToolClearance` for the contract.
protocol AgentTool: Sendable {
    /// Machine-readable tool name (e.g. "search_meetings").
    var name: String { get }
    /// Human-readable description for the LLM system prompt.
    var description: String { get }
    /// Permission tier that determines approval / biometric gating.
    var clearance: ToolClearance { get }
    /// MLX tool-calling JSON Schema. The tokenizer embeds this into the model's chat template.
    var spec: ToolSpec { get }
    /// Execute the tool with parsed arguments. Returns a result string for the LLM.
    /// Tools that access @MainActor singletons should scope `await MainActor.run { }` narrowly
    /// to just the data-fetch/mutation portion, keeping formatting off the main thread.
    func execute(arguments: [String: Any]) async throws -> String
}

// MARK: - AgentToolError

enum AgentToolError: Error, LocalizedError {
    case missingParameter(String)
    case invalidParameter(String, String)
    case executionFailed(String)
    case meetingNotFound(String)
    case documentNotFound(String)
    case spaceNotFound(String)
    case templateNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .missingParameter(name): "Missing required parameter: \(name)"
        case let .invalidParameter(name, reason): "Invalid parameter '\(name)': \(reason)"
        case let .executionFailed(reason): "Tool execution failed: \(reason)"
        case let .meetingNotFound(id): "Meeting not found: \(id)"
        case let .documentNotFound(id): "Document not found: \(id)"
        case let .spaceNotFound(id): "Space not found: \(id)"
        case let .templateNotFound(id): "Template not found: \(id)"
        }
    }
}
