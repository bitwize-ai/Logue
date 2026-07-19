import Foundation

// MARK: - High-Level Convenience Methods

extension LLMEngine {
    /// Writing assistant generation. Used by cross-app floating panel writing features.
    func generate(prompt: String) async throws -> String {
        // Truncate prompt to fit context window (~4 chars/token, reserve tokens for output + system)
        let maxChars = Self.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens)
        let safePrompt = String(prompt.prefix(maxChars))
        return try await complete(
            system: PromptRegistry.Convenience.generate.content,
            prompt: "<content>\n\(safePrompt)\n</content>"
        )
    }

    /// General-purpose AI assistant response for the AI Chat panel.
    func chat(prompt: String) async throws -> String {
        try await complete(
            system: PromptRegistry.Convenience.chat.content,
            prompt: prompt,
            maxTokens: 2048
        )
    }

    /// Meeting assistant for generating summaries and action items.
    func analyzeRaw(prompt: String) async throws -> String {
        try await complete(
            system: PromptRegistry.Convenience.analyzeRaw.content,
            prompt: prompt
        )
    }
}
