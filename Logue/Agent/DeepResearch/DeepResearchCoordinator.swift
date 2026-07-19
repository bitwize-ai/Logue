import Foundation
import MLXLMCommon
import os.log

/// Imperative 7-step Deep Research pipeline. Adapted from Sidekick's
/// `DeepResearchAgent.swift`, scaled down for Logue's local-MLX setting:
/// each section caps at 2-5 tool calls (instead of Sidekick's 7+) so a single
/// research run finishes in minutes, not hours.
///
/// Reuses existing infrastructure:
/// - `LLMEngine.complete()` and `completeWithTools()` (gate-serialized — no second model)
/// - `MemoryStore.recall()` for personalization
/// - `MLXToolDefinitions.dispatch()` for tool execution
/// - `MermaidRenderer` (via `RenderDiagramTool`) for diagrams
/// - `AgentConversationStore` for the final report
///
/// Differences from regular agent chat:
/// - Tools are auto-approved (the user already authorized the entire run)
/// - Constrained tool set: web_search, fetch_web_page, semantic_search_meetings,
///   semantic_search_documents, render_diagram. Web tools only included when the
///   user has enabled Web Search in Settings.
@MainActor @Observable
final class DeepResearchCoordinator {
    static let shared = DeepResearchCoordinator()

    // MARK: - State

    private(set) var isRunning: Bool = false
    private(set) var currentStep: DeepResearchStep = .idle
    private(set) var sections: [ResearchSection] = []
    private(set) var currentSectionIdx: Int = 0
    private(set) var lastError: String?
    /// Set to a non-empty array when `check_sufficiency` rejects the prompt;
    /// the UI surfaces these so the user can re-prompt.
    private(set) var clarifyingQuestions: [String] = []

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "DeepResearch")
    private var task: Task<Void, Never>?

    /// Tools constrained to retrieval / rendering — never mutating, never destructive.
    private static let constrainedToolNames: Set<String> = [
        "web_search",
        "fetch_web_page",
        "semantic_search_meetings",
        "semantic_search_documents",
        "render_diagram",
    ]

    private init() {}

    // MARK: - Public API

    /// Kicks off a Deep Research run for `prompt` and posts the final report to
    /// `conversationID`. The user message is expected to already be in the
    /// conversation (the chat view appends it before calling).
    func run(prompt: String, conversationID: UUID, oneShotWebSearch: Bool = false) {
        guard !isRunning else { return }
        task?.cancel()
        resetState()
        isRunning = true
        // Mirror the per-send override into AgentCoordinator's tool registry so
        // `constrainedToolSpecs()` (which reads from there) sees web tools for
        // this run only. Cleanup happens in `execute()`'s defer block.
        if oneShotWebSearch {
            AgentCoordinator.shared.setOneShotIncludeWebTools(true)
        }
        task = Task { [weak self] in
            guard let self else { return }
            await execute(prompt: prompt, conversationID: conversationID)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning {
            currentStep = .failed
            lastError = "Cancelled."
        }
        isRunning = false
    }

    /// Resets state without cancelling — used by the UI to dismiss completed/failed
    /// runs.
    func dismiss() {
        guard !isRunning else { return }
        resetState()
    }

    // MARK: - Pipeline

    // swiftlint:disable:next function_body_length
    private func execute(prompt: String, conversationID: UUID) async {
        defer {
            isRunning = false
            // Match the AgentCoordinator cleanup contract — clear any per-run
            // web-search override regardless of success/error/cancellation.
            if AgentCoordinator.shared.oneShotIncludeWebTools {
                AgentCoordinator.shared.setOneShotIncludeWebTools(false)
            }
        }

        let synthesizedPrompt: String
        do {
            // Step 1: check sufficiency
            currentStep = .checkingSufficiency
            try Task.checkCancellation()
            let sufficiency = try await checkSufficiency(prompt: prompt)
            switch sufficiency {
            case .sufficient:
                break
            case let .insufficient(questions):
                clarifyingQuestions = questions
                currentStep = .failed
                lastError = "Need more detail."
                postClarification(to: conversationID, questions: questions)
                return
            }

            // Step 2: synthesize prompt
            currentStep = .synthesizingPrompt
            try Task.checkCancellation()
            synthesizedPrompt = try await synthesizePrompt(prompt: prompt)

            // Step 3: plan sections
            currentStep = .planningSections
            try Task.checkCancellation()
            let plan = try await planSections(synthesizedPrompt: synthesizedPrompt)
            sections = plan
            guard !sections.isEmpty else {
                throw DeepResearchError.planEmpty
            }

            // Step 4: research each section (sections that need it)
            currentStep = .researching
            for idx in sections.indices {
                try Task.checkCancellation()
                currentSectionIdx = idx
                guard sections[idx].isSearchNeeded else { continue }
                let result = await researchSection(
                    synthesizedPrompt: synthesizedPrompt,
                    section: sections[idx]
                )
                sections[idx].findings = result.findings
                sections[idx].sources = result.sources
            }

            // Step 5: write draft
            currentStep = .writingDraft
            try Task.checkCancellation()
            var draft = try await writeDraft(
                synthesizedPrompt: synthesizedPrompt,
                sections: sections
            )

            // Step 6: create diagrams
            currentStep = .creatingDiagrams
            try Task.checkCancellation()
            draft = await augmentWithDiagrams(draft: draft)

            // Step 7: finalize
            currentStep = .finalizing
            try Task.checkCancellation()
            let finalReport = await (try? finalize(draft: draft)) ?? draft

            // Persist the report BEFORE flipping the step to .completed — if
            // posting throws (future refactor), we don't want the UI to claim
            // success while the conversation store has nothing.
            postReport(to: conversationID, report: finalReport)
            currentStep = .completed
        } catch is CancellationError {
            currentStep = .failed
            lastError = "Cancelled."
        } catch {
            currentStep = .failed
            lastError = error.localizedDescription
            logger.error("Deep Research failed: \(error.localizedDescription, privacy: .public)")
            postFailure(to: conversationID, error: error.localizedDescription)
        }
    }

    // MARK: - Step Implementations

    private enum SufficiencyResult {
        case sufficient
        case insufficient(questions: [String])
    }

    private func checkSufficiency(prompt: String) async throws -> SufficiencyResult {
        let response = try await LLMEngine.shared.complete(
            system: PromptRegistry.DeepResearch.checkSufficiencySystem.content,
            prompt: PromptRegistry.DeepResearch.checkSufficiencyPrompt(query: prompt),
            temperature: 0.0,
            maxTokens: 256
        )
        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let header = lines.first?.uppercased() ?? ""
        if header.hasPrefix("SUFFICIENT") {
            return .sufficient
        }
        if header.hasPrefix("INSUFFICIENT") {
            let questions = Array(lines.dropFirst()).filter { !$0.isEmpty }
            return .insufficient(questions: questions.isEmpty
                ? ["Could you clarify the scope of your research request?"]
                : questions
            )
        }
        // Ambiguous response → assume sufficient and let the next steps make sense of it.
        return .sufficient
    }

    private func synthesizePrompt(prompt: String) async throws -> String {
        let response = try await LLMEngine.shared.complete(
            system: PromptRegistry.DeepResearch.synthesizePromptSystem.content,
            prompt: PromptRegistry.DeepResearch.synthesizePromptPrompt(query: prompt),
            temperature: 0.2,
            maxTokens: 256
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prompt : trimmed
    }

    private func planSections(synthesizedPrompt: String) async throws -> [ResearchSection] {
        // Up to 3 attempts: standard prompt, then strict prompt, then strict + a JSON-only nudge.
        for attempt in 0 ..< 3 {
            let system = attempt == 0
                ? PromptRegistry.DeepResearch.planSectionsSystem.content
                : PromptRegistry.DeepResearch.planSectionsStrictSystem.content
            do {
                let response = try await LLMEngine.shared.complete(
                    system: system,
                    prompt: PromptRegistry.DeepResearch.planSectionsPrompt(synthesizedPrompt: synthesizedPrompt),
                    temperature: 0.2,
                    maxTokens: 1024
                )
                if let array = Self.extractJSONArray(from: response),
                   let parsed = Self.parseSections(json: array)
                {
                    return parsed
                }
                logger.warning("plan_sections JSON parse failed on attempt \(attempt + 1)")
            } catch {
                logger.warning("plan_sections LLM error on attempt \(attempt + 1): \(error.localizedDescription, privacy: .public)")
            }
            try Task.checkCancellation()
        }
        // Fallback: a single all-encompassing section the LLM can fill in via research.
        return [
            ResearchSection(
                title: "Overview",
                description: synthesizedPrompt,
                isSearchNeeded: true
            ),
        ]
    }

    private struct SectionResult {
        let findings: String
        let sources: [URL]
    }

    /// Per-section mini agent loop. Bounded to a few rounds; auto-approves all
    /// constrained tools (the user already authorized the whole run).
    private func researchSection(
        synthesizedPrompt: String,
        section: ResearchSection
    ) async -> SectionResult {
        let system = PromptRegistry.DeepResearch.researchSectionSystem(
            synthesizedPrompt: synthesizedPrompt,
            sectionTitle: section.title
        )
        let userPrompt = PromptRegistry.DeepResearch.researchSectionPrompt(
            sectionTitle: section.title,
            sectionDescription: section.description
        )
        let toolSpecs = constrainedToolSpecs()
        var messages: [[String: any Sendable]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": userPrompt],
        ]
        var aggregatedText = ""
        var sources: [URL] = []
        let maxRounds = 4
        let maxToolCalls = 5
        var totalToolCalls = 0

        for round in 0 ..< maxRounds {
            if Task.isCancelled {
                break
            }
            let outcome = await runResearchRound(
                round: round, messages: messages, toolSpecs: toolSpecs,
                maxToolCalls: maxToolCalls, totalToolCalls: totalToolCalls
            )
            messages = outcome.messages
            sources.append(contentsOf: outcome.sources)
            totalToolCalls = outcome.totalToolCalls
            if !outcome.text.isEmpty {
                aggregatedText = outcome.text
            }
            if outcome.shouldStop {
                break
            }
        }
        sources.append(contentsOf: Self.extractURLs(from: aggregatedText))
        return SectionResult(findings: aggregatedText, sources: Self.dedupeURLs(sources))
    }

    private struct RoundOutcome {
        var messages: [[String: any Sendable]]
        var text: String
        var sources: [URL]
        var totalToolCalls: Int
        var shouldStop: Bool
    }

    private func runResearchRound(
        round: Int,
        messages: [[String: any Sendable]],
        toolSpecs: [ToolSpec],
        maxToolCalls: Int,
        totalToolCalls: Int
    ) async -> RoundOutcome {
        var newMessages = messages
        var roundText = ""
        var roundToolCalls: [ToolCall] = []

        let stream = await LLMEngine.shared.completeWithTools(
            messages: newMessages, tools: toolSpecs,
            temperature: 0.3, maxTokens: 1024
        )
        do {
            for try await generation in stream {
                if Task.isCancelled {
                    break
                }
                switch generation {
                case let .chunk(text): roundText += text
                case let .toolCall(call): roundToolCalls.append(call)
                case .info: break
                }
            }
        } catch {
            logger.debug("research round \(round) errored: \(error.localizedDescription, privacy: .public)")
            return RoundOutcome(
                messages: newMessages,
                text: roundText,
                sources: [],
                totalToolCalls: totalToolCalls,
                shouldStop: true
            )
        }

        if !roundText.isEmpty {
            newMessages.append(["role": "assistant", "content": roundText] as [String: any Sendable])
        }
        if roundToolCalls.isEmpty {
            return RoundOutcome(
                messages: newMessages,
                text: roundText,
                sources: [],
                totalToolCalls: totalToolCalls,
                shouldStop: true
            )
        }

        var roundSources: [URL] = []
        var newTotal = totalToolCalls
        for call in roundToolCalls {
            if Task.isCancelled || newTotal >= maxToolCalls {
                break
            }
            newTotal += 1
            let result = await MLXToolDefinitions.dispatch(call)
            let truncated = String(result.output.prefix(AppConstants.AgentDefaults.toolResultMaxChars))
            let prefix = result.isError ? "ERROR: " : ""
            newMessages.append([
                "role": "tool", "content": "\(prefix)\(truncated)", "name": call.function.name,
            ] as [String: any Sendable])
            roundSources.append(contentsOf: Self.extractURLs(from: truncated))
        }
        return RoundOutcome(
            messages: newMessages, text: roundText, sources: roundSources,
            totalToolCalls: newTotal, shouldStop: newTotal >= maxToolCalls
        )
    }

    private func writeDraft(
        synthesizedPrompt: String,
        sections: [ResearchSection]
    ) async throws -> String {
        let block = sections.enumerated().map { idx, section in
            """
            ### Section \(idx + 1): \(section.title)
            Description: \(section.description)
            Findings:
            \(section.findings.isEmpty ? "(no findings — generate from general knowledge)" : section.findings)
            """
        }.joined(separator: "\n\n")

        let response = try await LLMEngine.shared.complete(
            system: PromptRegistry.DeepResearch.writeDraftSystem.content,
            prompt: PromptRegistry.DeepResearch.writeDraftPrompt(
                synthesizedPrompt: synthesizedPrompt,
                sectionsBlock: block
            ),
            temperature: 0.4,
            maxTokens: 4096
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks the LLM to suggest 0-3 diagrams, renders each via the RenderDiagramTool,
    /// and embeds the Markdown image refs back into the draft. Failures are
    /// silently dropped — diagrams are nice-to-have.
    private func augmentWithDiagrams(draft: String) async -> String {
        let response: String
        do {
            response = try await LLMEngine.shared.complete(
                system: PromptRegistry.DeepResearch.diagramOpportunitiesSystem.content,
                prompt: PromptRegistry.DeepResearch.diagramOpportunitiesPrompt(draft: draft),
                temperature: 0.3,
                maxTokens: 1024
            )
        } catch {
            return draft
        }
        guard let json = Self.extractRawJSONArray(from: response),
              let opportunities = Self.parseDiagramOpportunities(json: json),
              !opportunities.isEmpty
        else {
            return draft
        }

        var augmented = draft
        let renderTool = RenderDiagramTool()
        for opp in opportunities.prefix(3) {
            if Task.isCancelled {
                break
            }
            do {
                let rendered = try await renderTool.execute(
                    arguments: ["mermaid_code": opp.mermaid, "diagram_name": opp.section]
                )
                // The tool returns "Saved diagram to ...\n\nEmbed it ... ![Diagram](path)".
                // Pull out the Markdown image line.
                if let imageLine = rendered
                    .split(separator: "\n")
                    .map(String.init)
                    .first(where: { $0.contains("![") }),
                    let inserted = Self.insertAfterHeading(
                        in: augmented,
                        headingText: opp.section,
                        snippet: imageLine
                    )
                {
                    augmented = inserted
                }
            } catch {
                logger.debug("Diagram render failed for section '\(opp.section, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        return augmented
    }

    private func finalize(draft: String) async throws -> String {
        let response = try await LLMEngine.shared.complete(
            system: PromptRegistry.DeepResearch.finalizeSystem.content,
            prompt: PromptRegistry.DeepResearch.finalizePrompt(draft: draft),
            temperature: 0.2,
            maxTokens: 4096
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? draft : trimmed
    }

    // MARK: - Posting Results

    private func postClarification(to conversationID: UUID, questions: [String]) {
        let body = """
        I need a bit more detail before starting Deep Research:

        \(questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Reply with the missing context and I'll start the research.
        """
        AgentConversationStore.shared.appendMessage(
            AgentMessage(role: .assistant, content: body),
            to: conversationID
        )
        AgentConversationStore.shared.persistConversation(conversationID)
    }

    private func postReport(to conversationID: UUID, report: String) {
        AgentConversationStore.shared.appendMessage(
            AgentMessage(role: .assistant, content: report),
            to: conversationID
        )
        AgentConversationStore.shared.persistConversation(conversationID)
    }

    private func postFailure(to conversationID: UUID, error: String) {
        AgentConversationStore.shared.appendMessage(
            AgentMessage(role: .assistant, content: "Deep Research failed: \(error). Try again, or rephrase your request."),
            to: conversationID
        )
        AgentConversationStore.shared.persistConversation(conversationID)
    }

    private func resetState() {
        currentStep = .idle
        sections = []
        currentSectionIdx = 0
        lastError = nil
        clarifyingQuestions = []
    }

    // MARK: - Tool helpers

    private func constrainedToolSpecs() -> [ToolSpec] {
        AgentCoordinator.shared.registeredTools
            .filter { Self.constrainedToolNames.contains($0.name) }
            .map(\.spec)
    }

    // (JSON parsing, URL extraction, markdown insertion live in
    //  DeepResearchCoordinator+Helpers.swift to keep the type body under the
    //  450-line cap.)
}

// MARK: - Errors

enum DeepResearchError: Error, LocalizedError {
    case planEmpty

    var errorDescription: String? {
        switch self {
        case .planEmpty: "Couldn't plan the research — try rephrasing your prompt."
        }
    }
}
