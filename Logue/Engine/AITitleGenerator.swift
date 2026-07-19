import Foundation

/// Shared AI title generation utility used by both DocumentStore and MeetingStore.
/// Eliminates duplicated retry + clean logic.
enum AITitleGenerator {
    /// Generates a clean title from the LLM, retrying on failure.
    /// Returns nil if the model isn't loaded or all retries fail.
    static func generate(system: String? = nil, prompt: String) async -> String? {
        guard await LLMEngine.shared.isModelLoaded else { return nil }
        return await withRetryOptional {
            let raw = if let system {
                try await LLMEngine.shared.complete(system: system, prompt: prompt, maxTokens: 64)
            } else {
                try await LLMEngine.shared.generate(prompt: prompt)
            }
            return try cleanTitle(raw)
        }
    }

    /// Extracts and validates a title from raw LLM output.
    /// Throws on empty or oversized output to trigger retry.
    static func cleanTitle(_ raw: String) throws -> String {
        let firstLine = raw
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? raw

        let cleaned = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        guard !cleaned.isEmpty, cleaned.count <= 100 else {
            throw LLMError.emptyResponse
        }

        return cleaned
    }
}
