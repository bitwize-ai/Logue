import Foundation

/// An analysis request sent from WritingCoordinator to LLMEngine.
struct TextAnalysisRequest: Sendable {
    /// Full text content of the monitored field.
    let text: String
    /// Cursor offset (characters from start). 0 in Phase 1 (full-text analysis).
    let cursorOffset: Int
    /// Writing goal that shapes LLM behaviour.
    let goalMode: WritingGoalMode

    init(text: String, cursorOffset: Int = 0, goalMode: WritingGoalMode = .casual) {
        self.text = text
        self.cursorOffset = cursorOffset
        self.goalMode = goalMode
    }
}
