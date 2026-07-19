import Foundation

/// Structured error feedback returned to the LLM when a tool call fails to execute
/// because of malformed arguments, missing required parameters, or schema mismatch.
///
/// Mirrors Sidekick's `MalformedToolCall` pattern: instead of returning a terse error
/// string, we hand the model a clear description of what went wrong, the raw arguments
/// it sent, and an instruction to retry with valid input. The model can then self-correct
/// on the next reasoning round rather than aborting the agent loop.
struct MalformedToolCall {
    let toolName: String
    let rawArguments: String
    let errorDescription: String
    /// Number of times this tool has already been retried in the current turn. Used by
    /// the graph to cap correction loops.
    let priorRetries: Int

    /// Builds the feedback string the LLM sees as the tool's "result".
    /// Format mirrors Sidekick's: error first, raw args in a fenced block, then a clear
    /// instruction that this counts as a retry attempt.
    func getErrorFeedback() -> String {
        let retryHint = if priorRetries == 0 {
            "Please retry with valid arguments matching the tool's parameter schema."
        } else {
            """
            This is retry #\(priorRetries + 1). If you cannot determine the correct arguments, \
            stop calling this tool and explain to the user instead.
            """
        }

        return """
        Tool call '\(toolName)' failed to execute.

        Error: \(errorDescription)

        Raw arguments received:
        ```json
        \(rawArguments.isEmpty ? "{}" : rawArguments)
        ```

        \(retryHint)
        """
    }
}
