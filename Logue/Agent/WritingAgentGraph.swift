import Foundation
import LangGraph
import os.log

/// LangGraph-based multi-node writing analysis pipeline.
///
/// Graph topology:
/// ```
/// START → preprocess → grammar_check ─[conditional]─ clarity_check → finalize → END
///                                    └──────(quick)──────────────────────────────┘
/// ```
/// - `preprocess`: Pure Swift — extracts context window, computes readability stats.
/// - `grammar_check`: LLM call — grammar, spelling, punctuation suggestions.
/// - `clarity_check`: LLM call — clarity, conciseness, tone (business/academic/technical only, or long docs).
/// - `finalize`: Pure Swift — computes `WritingScore` from accumulated suggestions.
actor WritingAgentGraph {
    static let shared = WritingAgentGraph()
    private init() {}

    private var _graph: StateGraph<WritingAgentState>.CompiledGraph?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "WritingAgentGraph")

    // MARK: - Public Interface

    /// Runs the full analysis pipeline and returns the final state.
    func analyze(
        text: String,
        cursorOffset: Int,
        goalMode: WritingGoalMode
    ) async throws -> WritingAgentState {
        let graph = try getOrBuildGraph()
        let inputs: [String: Any] = [
            "text": text,
            "cursor_offset": cursorOffset,
            "goal_mode": goalMode.rawValue,
        ]
        logger.info("Starting analysis graph for \(text.count) chars, goal=\(goalMode.rawValue, privacy: .public)")
        let state = try await graph.invoke(.args(inputs))
        logger.info("Graph finished. grammar=\(state.grammarSuggestions?.count ?? 0) clarity=\(state.claritySuggestions?.count ?? 0)")
        return state
    }

    // MARK: - Graph Construction

    private func getOrBuildGraph() throws -> StateGraph<WritingAgentState>.CompiledGraph {
        if let cached = _graph {
            return cached
        }
        let compiled = try buildGraph()
        _graph = compiled
        return compiled
    }

    private func buildGraph() throws -> StateGraph<WritingAgentState>.CompiledGraph {
        let workflow = StateGraph(channels: WritingAgentState.schema) { WritingAgentState($0) }

        // ── Node: preprocess ───────────────────────────────────────────────────────────
        // Pure computation: extract context window + writing stats.
        try workflow.addNode("preprocess") { state in
            let text = state.text ?? ""
            let goalModeRaw = state.goalMode ?? WritingGoalMode.casual.rawValue
            let goalMode = WritingGoalMode(rawValue: goalModeRaw) ?? .casual
            let cursorOffset = state.cursorOffset ?? text.count

            let request = TextAnalysisRequest(text: text, cursorOffset: cursorOffset, goalMode: goalMode)
            let window = PromptBuilder.extractContextWindow(from: request)
            let stats = WritingStats.compute(from: text)

            return [
                "context_window": window,
                "word_count": stats.wordCount,
                "sentence_count": stats.sentenceCount,
                "reading_ease": stats.fleschReadingEase,
            ]
        }

        // ── Node: grammar_check ────────────────────────────────────────────────────────
        // LLM call for grammar, spelling, and punctuation.
        try workflow.addNode("grammar_check") { state in
            let items = try await LLMEngine.shared.runGrammarCheck(state: state)
            return ["grammar_suggestions": items]
        }

        // ── Node: clarity_check ────────────────────────────────────────────────────────
        // LLM call for clarity, conciseness, and tone analysis.
        try workflow.addNode("clarity_check") { state in
            let clarityItems = try await LLMEngine.shared.runClarityCheck(state: state)
            try Task.checkCancellation()
            let toneResult = try await LLMEngine.shared.runToneDetect(state: state)
            return [
                "clarity_suggestions": clarityItems,
                "tone_label": toneResult.label,
                "tone_confidence": toneResult.confidence,
            ]
        }

        // ── Node: finalize ─────────────────────────────────────────────────────────────
        // Compute WritingScore from accumulated suggestions.
        try workflow.addNode("finalize") { state in
            let grammarCount = state.grammarSuggestions?.count ?? 0
            let clarityCount = state.claritySuggestions?.count
            let wordCount = state.wordCount ?? 0

            let score = WritingScore.compute(
                grammarCount: grammarCount,
                clarityCount: clarityCount,
                wordCount: wordCount
            )
            return ["overall_score": score.overall]
        }

        // ── Edges ─────────────────────────────────────────────────────────────────────
        try workflow
            .addEdge(sourceId: START, targetId: "preprocess")
            .addEdge(sourceId: "preprocess", targetId: "grammar_check")
            .addConditionalEdge(
                sourceId: "grammar_check",
                condition: { @MainActor state -> String in
                    let wordCount = state.wordCount ?? 0
                    // Deep analysis only for longer documents
                    let needsDeep = wordCount > 40
                    return needsDeep ? "deep" : "quick"
                },
                edgeMapping: [
                    "deep": "clarity_check",
                    "quick": "finalize",
                ]
            )
            .addEdge(sourceId: "clarity_check", targetId: "finalize")
            .addEdge(sourceId: "finalize", targetId: END)

        return try workflow.compile()
    }
}
