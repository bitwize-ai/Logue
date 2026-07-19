import Foundation

// MARK: - LLMPromptMessage (replaces LLMInput.Message from LocalLLMClient)

/// Lightweight message type for prompt construction. Replaces `LLMInput.Message` from the
/// removed LocalLLMClient dependency. Used by `PromptBuilder` and `LLMEngine+WritingAnalysis`.
struct LLMPromptMessage {
    enum Role { case system, user, assistant }
    let role: Role
    let content: String

    static func system(_ content: String) -> LLMPromptMessage {
        .init(role: .system, content: content)
    }

    static func user(_ content: String) -> LLMPromptMessage {
        .init(role: .user, content: content)
    }
}

/// Constructs LLM message arrays for grammar analysis, rephrasing, and tone detection.
/// Pure value type — no state, fully testable.
/// Prompts are sourced from `PromptRegistry.Analysis`.
enum PromptBuilder {
    // MARK: - Grammar Analysis (correctness)

    static func messages(for request: TextAnalysisRequest) -> [LLMPromptMessage] {
        [
            .system(systemPrompt(for: request.goalMode)),
            .user(userMessage(for: request)),
        ]
    }

    static func systemPrompt(for goalMode: WritingGoalMode) -> String {
        PromptRegistry.Analysis.grammarSystem(for: goalMode).content
    }

    static func userMessage(for request: TextAnalysisRequest) -> String {
        let contextWindow = extractContextWindow(from: request)
        return "Analyse this text:\n\n\(contextWindow)"
    }

    // MARK: - Clarity & Conciseness Analysis

    static func claritySystemPrompt(for goalMode: WritingGoalMode) -> String {
        PromptRegistry.Analysis.claritySystem(for: goalMode).content
    }

    // MARK: - Rephrase

    static func rephraseMessages(text: String, style: WritingGoalMode) -> [LLMPromptMessage] {
        [
            .system(PromptRegistry.Analysis.rephraseSystem(style: style).content),
            .user(text),
        ]
    }

    // MARK: - Tone Detection

    static func toneMessages(text: String) -> [LLMPromptMessage] {
        [
            .system(PromptRegistry.Analysis.toneSystem.content),
            .user(text),
        ]
    }

    // MARK: - Context Window

    /// Extracts a context window centred on the cursor position.
    /// Internal so `WritingAgentGraph` nodes can call it directly.
    static func extractContextWindow(from request: TextAnalysisRequest) -> String {
        let text = request.text
        let maxLength = AppConstants.LLMDefaults.contextWindowSize

        guard text.count > maxLength else { return text }

        let halfWindow = maxLength / 2
        let cursorOffset = min(request.cursorOffset, text.count)

        let rawStart = max(0, cursorOffset - halfWindow)
        let clampedStart = min(rawStart, max(0, text.count - maxLength))

        let startIndex = text.index(text.startIndex, offsetBy: clampedStart)
        let remainingLength = min(maxLength, text.count - clampedStart)
        let endIndex = text.index(startIndex, offsetBy: remainingLength)

        var window = String(text[startIndex ..< endIndex])

        if clampedStart > 0 {
            window = "…" + window
        }
        if text.index(text.startIndex, offsetBy: clampedStart + remainingLength) < text.endIndex {
            window += "…"
        }

        return window
    }
}
