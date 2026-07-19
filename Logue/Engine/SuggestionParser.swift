import Foundation
import os.log

/// Incrementally parses streaming JSON tokens from LLMEngine into Suggestion values.
///
/// Uses brace-depth counting to detect when the model has emitted a complete JSON object,
/// then decodes it. This gives a progressive reveal: suggestions appear as the model streams
/// rather than waiting for the full response.
struct SuggestionParser {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "SuggestionParser")
    private var buffer = ""
    private var braceDepth = 0

    /// Feed the next token from the LLM stream.
    /// Returns any Suggestion values that became parseable from this token.
    mutating func consume(token: String) -> [Suggestion] {
        buffer += token

        for char in token {
            switch char {
            case "{": braceDepth += 1
            case "}": if braceDepth > 0 {
                    braceDepth -= 1
                }
            default: break
            }
        }

        // Attempt a parse when we've seen at least one opening brace and depth is balanced.
        guard braceDepth == 0, buffer.contains("{") else { return [] }
        return attemptParse()
    }

    /// Call after the stream ends to parse any remaining buffered content.
    mutating func flush() -> [Suggestion] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return attemptParse()
    }

    // MARK: - Private

    private mutating func attemptParse() -> [Suggestion] {
        // Find the outermost JSON object boundaries robustly
        guard let jsonString = extractOutermostObject(from: buffer) else { return [] }
        guard let data = jsonString.data(using: .utf8) else { return [] }

        do {
            let response = try JSONDecoder().decode(SuggestionResponse.self, from: data)
            reset()
            return response.suggestions.map { $0.toDomain() }
        } catch {
            // Log if balanced braces but still invalid JSON (likely malformed LLM output)
            if braceDepth == 0 {
                Self.logger.warning("Balanced JSON failed to decode: \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
    }

    /// Extracts the outermost `{ ... }` JSON object from a string,
    /// trimming any leading/trailing noise the model may have emitted.
    private func extractOutermostObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}")
        else { return nil }
        guard start <= end else { return nil }
        return String(text[start ... end])
    }

    private mutating func reset() {
        buffer = ""
        braceDepth = 0
    }
}
