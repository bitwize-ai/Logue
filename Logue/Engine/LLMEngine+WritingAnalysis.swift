import Foundation

// MARK: - LangGraph Writing Analysis Nodes

extension LLMEngine {
    /// Called by the `grammar_check` node. Returns all grammar/spelling/punctuation items.
    /// Routes through `complete()` to participate in the `inferenceGate` serialization chain,
    /// preventing session races with concurrent AI operations.
    func runGrammarCheck(state: WritingAgentState) async throws -> [SuggestionResponse.SuggestionItem] {
        let contextWindow = truncatedContext(state.contextWindow ?? state.text ?? "", reservedTokens: 2048 + 256)
        let goalMode = WritingGoalMode(rawValue: state.goalMode ?? WritingGoalMode.casual.rawValue) ?? .casual
        let system = PromptBuilder.systemPrompt(for: goalMode)
        let prompt = "Analyse this text:\n\n<content>\(contextWindow)</content>"

        let rawOutput = try await complete(system: system, prompt: prompt, maxTokens: 2048)
        return LLMResponseParser.parseSuggestionItems(from: rawOutput)
    }

    /// Called by the `clarity_check` node. Returns clarity/conciseness/style items.
    /// Routes through `complete()` to participate in the `inferenceGate` serialization chain.
    func runClarityCheck(state: WritingAgentState) async throws -> [SuggestionResponse.SuggestionItem] {
        let contextWindow = truncatedContext(state.contextWindow ?? state.text ?? "", reservedTokens: 2048 + 256)
        let goalMode = WritingGoalMode(rawValue: state.goalMode ?? WritingGoalMode.casual.rawValue) ?? .casual
        let system = PromptBuilder.claritySystemPrompt(for: goalMode)
        let prompt = "Analyse clarity and style:\n\n<content>\(contextWindow)</content>"

        let rawOutput = try await complete(system: system, prompt: prompt, maxTokens: 2048)
        return LLMResponseParser.parseSuggestionItems(from: rawOutput)
    }

    /// Called by the `tone_detect` node. Returns detected tone label + confidence.
    /// Routes through `complete()` to participate in the `inferenceGate` serialization chain.
    func runToneDetect(state: WritingAgentState) async throws -> ToneResult {
        let contextWindow = truncatedContext(state.contextWindow ?? state.text ?? "", reservedTokens: 256 + 256)
        let wrappedContent = "<content>\(contextWindow)</content>"
        let messages = PromptBuilder.toneMessages(text: wrappedContent)

        // Extract by role — resilient to array layout changes
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userPrompt = messages.first(where: { $0.role == .user })?.content ?? wrappedContent

        let rawOutput = try await complete(system: system, prompt: userPrompt, maxTokens: 256)
        return LLMResponseParser.parseToneResult(from: rawOutput)
    }

    /// Rephrase text in the given writing style.
    /// Routes through `complete()` to participate in the `inferenceGate` serialization chain
    /// for both local and API paths, preventing session races.
    func rephrase(_ text: String, style: WritingGoalMode) async throws -> String {
        let safeText = truncatedContext(text, reservedTokens: 512 + 256)
        let messages = PromptBuilder.rephraseMessages(text: safeText, style: style)
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userPrompt = messages.first(where: { $0.role == .user })?.content ?? safeText
        return try await complete(system: system, prompt: userPrompt, maxTokens: 512)
    }

    /// Truncates input text to fit within the model's context window,
    /// breaking at the last word boundary to avoid sending partial words to the LLM.
    private func truncatedContext(_ text: String, reservedTokens: Int) -> String {
        let maxChars = Self.maxInputChars(reservedTokens: reservedTokens)
        guard text.count > maxChars else { return text }
        let prefix = String(text.prefix(maxChars))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace])
        }
        return prefix
    }
}
