import Foundation
import os.log

/// Handles a single inline-rewrite request: sanitizes input, respects the model's
/// context window, routes through `LLMEngine.complete()` so the call participates in
/// the shared `inferenceGate` serialization.
///
/// Separate from `AgentChatGraph` — no tool calls needed for a straightforward rewrite,
/// so we skip the graph overhead and hit the model directly.
enum InlineRewriteEngine {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "InlineRewriteEngine")

    /// Maximum allowed length of the user's instruction. Keeps prompts lean and
    /// protects against runaway input.
    static let maxInstructionLength = 500

    /// Reserved token budget for the model's output + system prompt overhead.
    private static let reservedTokens = 1024

    /// Errors surfaced to the UI.
    enum RewriteError: LocalizedError {
        case emptyInstruction
        case emptySelection
        case llmFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyInstruction: "Add an instruction to tell the AI what to change."
            case .emptySelection: "Select some text first."
            case let .llmFailed(message): "Rewrite failed: \(message)"
            }
        }
    }

    /// Runs one rewrite. Returns the rewritten text or throws a `RewriteError`.
    /// The caller is responsible for replacing the original selection with the result.
    static func rewrite(selection: String, instruction: String) async throws -> String {
        let sanitizedInstruction = sanitize(instruction: instruction)
        guard !sanitizedInstruction.isEmpty else { throw RewriteError.emptyInstruction }

        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { throw RewriteError.emptySelection }

        let truncatedSelection = truncateSelection(selection)

        logger.info("Rewriting \(truncatedSelection.count) chars with instruction of \(sanitizedInstruction.count) chars")

        do {
            let result = try await LLMEngine.shared.complete(
                system: PromptRegistry.InlineRewrite.system.content,
                prompt: PromptRegistry.InlineRewrite.userPrompt(
                    instruction: sanitizedInstruction,
                    selectedText: truncatedSelection
                ),
                maxTokens: 2048
            )
            let cleaned = stripLeadingPreamble(result)
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RewriteError.llmFailed("empty response")
            }
            return cleaned
        } catch let error as RewriteError {
            throw error
        } catch {
            logger.error("Rewrite LLM call failed: \(error.localizedDescription, privacy: .public)")
            throw RewriteError.llmFailed(error.localizedDescription)
        }
    }

    /// Returns true if the selection had to be truncated to fit the context window.
    static func wasTruncated(selection: String) -> Bool {
        selection.count > LLMEngine.maxInputChars(reservedTokens: reservedTokens)
    }

    // MARK: - Helpers

    /// Sanitizes the instruction per CLAUDE.md rules: truncate, strip control chars + newlines.
    private static func sanitize(instruction: String) -> String {
        String(instruction.prefix(maxInstructionLength))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncates the selection to fit within the context window budget.
    private static func truncateSelection(_ selection: String) -> String {
        let maxChars = LLMEngine.maxInputChars(reservedTokens: reservedTokens)
        guard selection.count > maxChars else { return selection }
        return String(selection.prefix(maxChars))
    }

    /// Strips common model preambles ("Here is...", "Rewritten:", surrounding quotes, code fences).
    /// Small local models sometimes ignore the "no preamble" rule; this is a safety net.
    private static func stripLeadingPreamble(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip common code fences
        if out.hasPrefix("```") {
            // Drop first line (fence + optional lang) and trailing fence
            if let firstNewline = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: firstNewline)...])
            }
            if let fenceEnd = out.range(of: "```", options: .backwards) {
                out = String(out[..<fenceEnd.lowerBound])
            }
        }

        // Strip outer matching quotes
        if out.hasPrefix("\""), out.hasSuffix("\""), out.count > 1 {
            out = String(out.dropFirst().dropLast())
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
