import Foundation
import LangGraph
import MLXLMCommon
import os.log

/// Coordinates the agentic chat — consumes LangGraph `stream()` with real-time
/// token-level streaming, checkpoint-based thread management, user-approval gating
/// for destructive tools, and structured error handling.
@MainActor @Observable
final class AgentCoordinator {
    static let shared = AgentCoordinator()

    // MARK: - State

    private(set) var isProcessing = false
    private(set) var streamingText = ""
    private(set) var isStreaming = false
    private(set) var activeToolCalls: [AgentToolCall] = []

    /// Last conversation-level error surfaced to the UI. Cleared automatically on the
    /// next `send`/`regenerate`, or explicitly via `dismissError()`.
    /// Stays set even after `isStreaming` flips to false, so the UI can show a
    /// persistent banner until the user acknowledges or sends again.
    private(set) var lastError: String?

    private var processingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AgentCoordinator")

    // MARK: - Tool Registry

    private(set) var registeredTools: [any AgentTool] = []

    /// UserDefaults observer token for the web-search master toggle. Re-registers
    /// tools when the user flips the switch in Settings.
    private var webSearchPrefObserver: NSObjectProtocol?

    /// Per-send override that forces the web-search tools into the registry for the
    /// duration of one agent run, regardless of the Settings master toggle.
    /// Set by `send`/`sendWithoutAppendingUser` (and by `DeepResearchCoordinator`)
    /// when the user flips the chat input bar's one-shot Search toggle. Always
    /// reset in the `runGraph` `defer` block so the next regular send is unaffected.
    private(set) var oneShotIncludeWebTools = false

    private init() {
        registerDefaultTools()
        // Re-register on toggle changes so Settings can flip web tools live.
        webSearchPrefObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            // The notification fires for every default change — cheap to check
            // and only mutate if the registered set actually differs.
            Task { @MainActor [weak self] in
                self?.refreshRegisteredToolsIfNeeded()
            }
        }
    }

    /// Rebuilds `registeredTools` to match the current opt-in state. Called by
    /// the UserDefaults observer and by send paths flipping `oneShotIncludeWebTools`.
    /// Idempotent.
    func refreshRegisteredToolsIfNeeded() {
        let target = buildToolRegistry()
        let currentNames = registeredTools.map(\.name)
        let targetNames = target.map(\.name)
        if currentNames != targetNames {
            registeredTools = target
        }
    }

    /// Sets the per-send web-tool override. Called by `DeepResearchCoordinator`
    /// before its pipeline starts so the constrained tool list visible to
    /// `research_section` includes web search even when Settings has it disabled.
    /// Pair every `setOneShotIncludeWebTools(true)` with a matching `false` in a
    /// `defer` block on the caller's side to guarantee cleanup.
    func setOneShotIncludeWebTools(_ enabled: Bool) {
        oneShotIncludeWebTools = enabled
        refreshRegisteredToolsIfNeeded()
    }

    private func registerDefaultTools() {
        registeredTools = buildToolRegistry()
    }

    /// Source of truth for the tool registry. Conditionally includes web tools
    /// when either the Settings master toggle is on or a per-send override
    /// (`oneShotIncludeWebTools`) is set.
    private func buildToolRegistry() -> [any AgentTool] {
        var tools = Self.readOnlyTools()
            + Self.writeTools()
            + Self.aiContentTools()
            + Self.appleNativeTools()
            + Self.computeAndDialogTools()
            + Self.fileSystemTools()

        // Phase A: per-tool enable/disable filter. The AISettingsTab persists
        // a set of tool names the user has explicitly turned off (e.g. "I
        // never want the agent to delete documents"). Strip those from the
        // registry on every rebuild so toggling is immediate.
        let disabledNames = Self.disabledToolNames()
        if !disabledNames.isEmpty {
            tools.removeAll { disabledNames.contains($0.name) }
        }
        // Web search tools — included when the Settings master toggle is on
        // OR when a per-send override (the input bar's one-shot Search toggle)
        // is active for this run.
        let userOptedIn = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.webSearchEnabled)
        if userOptedIn || oneShotIncludeWebTools {
            tools.append(WebSearchTool())
            tools.append(FetchWebPageTool())
        }
        return tools
    }

    // MARK: - Tool registry shards

    //
    // The full registry is composed from these helpers in `buildToolRegistry`.
    // Splitting keeps each function under SwiftLint's body-length cap and
    // gives a single place to look up which tools exist in each category.

    private static func readOnlyTools() -> [any AgentTool] {
        [
            ListMeetingsTool(),
            SearchMeetingsTool(),
            SemanticSearchMeetingsTool(),
            GetMeetingDetailsTool(),
            GetTranscriptTool(),
            GetActionItemsTool(),
            GetDailyDigestTool(),
            ListDocumentsTool(),
            SearchDocumentsTool(),
            SemanticSearchDocumentsTool(),
            GetDocumentTool(),
            GetUpcomingEventsTool(),
        ]
    }

    private static func writeTools() -> [any AgentTool] {
        [
            CreateDocumentTool(),
            UpdateDocumentTool(),
            DeleteDocumentTool(),
            MoveDocumentTool(),
            AddDocumentTagTool(),
            CreateSpaceTool(),
            RenameSpaceTool(),
            DeleteSpaceTool(),
            CreateCalendarEventTool(),
            UpdateCalendarEventTool(),
            DeleteCalendarEventTool(),
            ListTemplatesTool(),
            CreateDocumentFromTemplateTool(),
            ExportDocumentPDFTool(),
        ]
    }

    private static func aiContentTools() -> [any AgentTool] {
        [
            SummarizeDocumentTool(),
            RephraseTextTool(),
            GrammarCheckTool(),
            ClarityCheckTool(),
            ToneDetectTool(),
            FactCheckDocumentTool(),
            DetectPIITool(),
            RenderDiagramTool(),
            GenerateSlideDeckTool(),
        ]
    }

    private static func appleNativeTools() -> [any AgentTool] {
        [
            DraftEmailTool(),
            FetchContactsTool(),
            GetRemindersTool(),
            AddReminderTool(),
            UpdateReminderTool(),
            DeleteReminderTool(),
            GetLocationTool(),
        ]
    }

    private static func computeAndDialogTools() -> [any AgentTool] {
        [
            RunJavaScriptTool(),
            GetConfirmationTool(),
            GetTextInputTool(),
            GetUserSelectionTool(),
        ]
    }

    /// Phase G: external filesystem access. Sandbox-safe via
    /// `FileAccessGate` — first call to a new folder prompts the user
    /// via `NSOpenPanel` for an explicit grant.
    private static func fileSystemTools() -> [any AgentTool] {
        [
            ListDirectoryTool(),
            ReadFileAtPathTool(),
            WriteTextToFileTool(),
            DeleteFileAtPathTool(),
        ]
    }

    /// Per-tool disable set. Persisted by `AISettingsTab` as a comma-separated
    /// list of tool names. The registry rebuilds on every send (via the
    /// observer in `AISettingsTab`), so toggling is effectively immediate.
    static func disabledToolNames() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.disabledAgentTools) ?? ""
        return Set(raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    // MARK: - Public API

    func send(
        message: String,
        conversationID: UUID,
        attachments: [TempAttachment] = [],
        oneShotWebSearch: Bool = false
    ) {
        guard !isProcessing else { return }
        lastError = nil
        processingTask?.cancel()
        if oneShotWebSearch {
            setOneShotIncludeWebTools(true)
        }
        let userMessage = AgentMessage(role: .user, content: message, attachments: attachments)
        // Defer cleanup of the per-send override into the Task body so it fires
        // even if the Task is cancelled before `runGraph` is awaited (the
        // `runGraph` defer alone is not sufficient — a Task cancelled before its
        // first await may never enter `runGraph` at all).
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if oneShotWebSearch {
                    Task { @MainActor [weak self] in
                        self?.setOneShotIncludeWebTools(false)
                    }
                }
            }
            AgentConversationStore.shared.appendMessage(userMessage, to: conversationID)
            await runGraph(conversationID: conversationID)
        }
    }

    func sendWithoutAppendingUser(conversationID: UUID, oneShotWebSearch: Bool = false) {
        guard !isProcessing else { return }
        lastError = nil
        processingTask?.cancel()
        if oneShotWebSearch {
            setOneShotIncludeWebTools(true)
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if oneShotWebSearch {
                    Task { @MainActor [weak self] in
                        self?.setOneShotIncludeWebTools(false)
                    }
                }
            }
            await runGraph(conversationID: conversationID)
        }
    }

    /// Clears the last surfaced error. Called when the user dismisses the error banner.
    func dismissError() {
        lastError = nil
    }

    /// Regenerates the assistant response from an edited user message. Truncates every
    /// message after `messageID`, replaces the user message body with `newContent`, and
    /// restarts the agent loop. If the coordinator is already processing, the request
    /// is ignored (UI should disable the edit affordance in that state).
    func regenerateFromUserMessage(messageID: UUID, in conversationID: UUID, newContent: String) {
        guard !isProcessing else { return }
        lastError = nil
        processingTask?.cancel()
        // Resolve any dangling approvals before we overwrite the conversation tail.
        Task { await ApprovalGate.shared.rejectAllPending() }
        processingTask = Task { [weak self] in
            guard let self else { return }
            let store = AgentConversationStore.shared
            store.truncateMessagesAfter(messageID: messageID, in: conversationID)
            store.updateUserMessageContent(messageID: messageID, in: conversationID, content: newContent)
            await runGraph(conversationID: conversationID)
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        isStreaming = false
        streamingText = ""
        activeToolCalls = []
        // Belt-and-braces: if the cancelled Task hadn't reached its `defer` yet
        // (e.g. cancel landed before the Task's body started), the per-send web
        // override is still set. Drop it here so the next send isn't poisoned.
        if oneShotIncludeWebTools {
            setOneShotIncludeWebTools(false)
        }
        // Resolve any outstanding approval prompts so downstream awaits don't leak.
        Task { await ApprovalGate.shared.rejectAllPending() }
    }

    // (Approval API + handler + tool-result posting live in
    //  AgentCoordinator+Approval.swift to keep this type body under the cap.)

    // MARK: - Graph Execution

    // Orchestrates the full agent loop: streaming, node output handling, tool result posting, cleanup.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func runGraph(conversationID: UUID) async {
        isProcessing = true
        streamingText = ""
        isStreaming = false
        activeToolCalls = []
        defer {
            isProcessing = false
            isStreaming = false
            streamingText = ""
            activeToolCalls = []
            // Reset any per-send web-search override so the next regular send
            // doesn't accidentally inherit it (success, error, and cancellation
            // all flow through this defer).
            if oneShotIncludeWebTools {
                setOneShotIncludeWebTools(false)
            }
        }

        let store = AgentConversationStore.shared

        // Auto-title
        if let conv = store.conversations.first(where: { $0.id == conversationID }),
           conv.title == "New Conversation",
           let lastUser = conv.messages.last(where: { $0.role == .user })
        {
            store.updateTitle(String(lastUser.content.prefix(60)), for: conversationID)
        }

        // Check model
        let isLoaded = await LLMEngine.shared.isModelLoaded
        guard isLoaded else {
            store.appendMessage(
                AgentMessage(role: .assistant, content: "No AI model is loaded. Please select a model in Settings."),
                to: conversationID
            )
            return
        }

        let lastUserMessage = store.conversations
            .first(where: { $0.id == conversationID })?
            .messages.last(where: { $0.role == .user })
        let query = lastUserMessage?.content ?? ""
        let attachments = lastUserMessage?.attachments ?? []
        let userMessageID = lastUserMessage?.id

        // Best-effort memory extraction. Triggered here (not in `send`) so both the
        // `send` and `sendWithoutAppendingUser` code paths benefit. Detached + utility
        // priority so it doesn't delay the agent loop — gate-serialization in
        // `LLMEngine` handles ordering against the foreground reasoning call.
        if !query.isEmpty {
            Task.detached(priority: .utility) {
                await MemoryStore.shared.rememberIfNeeded(
                    userMessage: query, messageID: userMessageID
                )
            }
        }

        // Recall any relevant memories for this query — inject into the system prompt.
        // Off-main, awaitable; falls back to [] on any error so the agent still runs.
        let recalledMemories = await MemoryStore.shared.recall(query: query, k: 5)

        let messages = buildMessages(
            for: conversationID,
            currentQuery: query,
            memories: recalledMemories,
            attachments: attachments
        )
        let tools = MLXToolDefinitions.buildToolSpecs()
        let threadId = conversationID.uuidString

        // Set up token-level streaming callback
        isStreaming = true
        streamingText = ""
        // Create placeholder for streaming reasoning
        store.appendMessage(AgentMessage(role: .assistant, content: ""), to: conversationID)

        await AgentChatGraph.shared.setCallbacks(
            onToken: { [weak self] token in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    streamingText += token
                    store.updateLastAssistantMessage(in: conversationID, content: streamingText)
                }
            },
            onToolCall: { _ in
                // Tool call detected during streaming — card is posted after execution
                // (or by the approval gate if the tool is destructive).
            },
            onApprovalRequired: { [weak self] toolCallID, toolName, argsJSON, clearance in
                await self?.handleApprovalRequest(
                    toolCallID: toolCallID,
                    toolName: toolName,
                    argsJSON: argsJSON,
                    clearance: clearance,
                    conversationID: conversationID
                ) ?? .rejected
            }
        )

        // Stream the graph
        let graphStream: AsyncThrowingStream<NodeOutput<AgentChatState>, Error>
        do {
            graphStream = try await AgentChatGraph.shared.stream(
                query: query,
                messages: messages,
                tools: tools,
                threadId: threadId
            )
        } catch {
            logger.error("Failed to start agent graph: \(error.localizedDescription)")
            lastError = "Couldn't start the agent: \(error.localizedDescription)"
            store.updateLastAssistantMessage(
                in: conversationID,
                content: "I encountered an error starting the agent. Please try again."
            )
            isStreaming = false
            await AgentChatGraph.shared.clearCallbacks()
            return
        }

        // Consume node outputs
        var previousToolResultCount = 0

        do {
            for try await nodeOutput in graphStream {
                guard !Task.isCancelled else { break }

                switch nodeOutput.node {
                case "agent_reason":
                    let state = nodeOutput.state
                    let reasoning = state.reasoningText ?? ""
                    let hasTools = state.hasToolCalls ?? false
                    let error = state.errorMessage ?? ""

                    // Handle errors
                    if !error.isEmpty {
                        lastError = error
                        store.updateLastAssistantMessage(in: conversationID, content: error)
                        isStreaming = false
                        await AgentChatGraph.shared.clearCallbacks()
                        store.persistConversation(conversationID)
                        return
                    }

                    if hasTools {
                        // Finalize the streaming reasoning text (if any) before tool cards
                        if !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.updateLastAssistantMessage(in: conversationID, content: streamingText)
                        } else {
                            // Remove empty placeholder
                            store.removeLastAssistantMessage(from: conversationID)
                        }
                        // Reset streaming for next round
                        streamingText = ""
                    } else {
                        // No tools — streaming text is the final answer
                        if !streamingText.isEmpty {
                            store.updateLastAssistantMessage(in: conversationID, content: streamingText)
                        }
                        _ = reasoning // preserved intentionally — kept for future diagnostics
                    }

                case "execute_tools":
                    let state = nodeOutput.state
                    let results = state.toolResults ?? []

                    // Post only NEW results from this round
                    let newResults = Array(results.dropFirst(previousToolResultCount))
                    previousToolResultCount = results.count

                    for result in newResults {
                        postToolResult(result, in: conversationID)
                    }
                    activeToolCalls = []

                    // Create new placeholder for next reasoning round
                    streamingText = ""
                    store.appendMessage(AgentMessage(role: .assistant, content: ""), to: conversationID)

                default:
                    break
                }
            }
        } catch {
            logger.error("Agent graph stream error: \(error.localizedDescription)")
            lastError = "Agent stream failed: \(error.localizedDescription)"
            if streamingText.isEmpty {
                store.updateLastAssistantMessage(
                    in: conversationID, content: "I encountered an error. Please try again."
                )
            }
        }

        isStreaming = false
        await AgentChatGraph.shared.clearCallbacks()

        // Clean up: if last assistant message is empty (no final answer), remove it
        if let conv = store.conversations.first(where: { $0.id == conversationID }),
           let lastMsg = conv.messages.last,
           lastMsg.role == .assistant, lastMsg.content.isEmpty
        {
            store.removeLastAssistantMessage(from: conversationID)
        }

        // If we have no assistant answer at all, post a fallback
        if let conv = store.conversations.first(where: { $0.id == conversationID }),
           !conv.messages.contains(where: { $0.role == .assistant && !$0.content.isEmpty })
        {
            store.appendMessage(
                AgentMessage(role: .assistant, content: "I wasn't able to generate a response. Please try rephrasing."),
                to: conversationID
            )
        }

        store.persistConversation(conversationID)
    }

    // MARK: - Message Building

    /// Builds the full message array for the LLM, including system prompt and conversation history.
    /// Injects any recalled cross-conversation memories into the system prompt as a
    /// `<user_memories>` block, and any per-message attachments into the user turn as
    /// `<attached_file>` blocks. Validates total character count against the model's
    /// context window and truncates history from oldest if budget is exceeded.
    private func buildMessages(
        for conversationID: UUID,
        currentQuery: String,
        memories: [String] = [],
        attachments: [TempAttachment] = []
    ) -> [[String: any Sendable]] {
        let store = AgentConversationStore.shared
        // Tailor the system prompt to the current run. Without this, the LLM
        // reads `Web (opt-in, only when enabled in Settings)` and treats web
        // tools as off-limits even when they're registered. Worse: when the
        // user toggles the per-message "Search" pill, a generic prompt gives
        // the model no signal to actually call web_search.
        let webSearchAvailable = registeredTools.contains { tool in
            tool.name == "web_search" || tool.name == "fetch_web_page"
        }
        let systemContent = PromptRegistry.Agent.systemPrompt(
            webSearchAvailable: webSearchAvailable,
            oneShotWebSearch: oneShotIncludeWebTools
        ) + PromptRegistry.Memory.recallBlock(memories: memories)
        let maxChars = LLMEngine.maxInputChars(
            reservedTokens: AppConstants.AgentDefaults.reservedTokens + AppConstants.AgentDefaults.maxResponseTokens
        )

        // Build the user turn: query plus any attached-file blocks. Attachments
        // appended after the question give the LLM a clean separation between the
        // ask and the supporting material.
        var userTurn = currentQuery
        if !attachments.isEmpty {
            for attachment in attachments {
                userTurn += attachment.injectionBlock()
            }
        }

        // Cap the user turn to fit alongside the system prompt + history budget.
        let cappedUserTurn = String(userTurn.prefix(maxChars))

        guard let conv = store.conversations.first(where: { $0.id == conversationID }) else {
            return [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": cappedUserTurn],
            ]
        }

        // Include recent user/assistant exchanges (not tool messages — those are per-session)
        let candidateHistory = conv.messages
            .filter { $0.role == .user || ($0.role == .assistant && !$0.content.isEmpty) }
            .suffix(8)
            .dropLast() // Exclude current user message (will be added below)

        // Compute fixed overhead: system prompt + current user turn (with attachments)
        let fixedChars = systemContent.count + cappedUserTurn.count

        // Add history from most-recent, trimming oldest if we exceed the budget
        var historyMessages: [(role: String, content: String)] = []
        var totalChars = fixedChars
        for msg in candidateHistory.reversed() {
            let role = msg.role == .user ? "user" : "assistant"
            let charCount = msg.content.count
            if totalChars + charCount > maxChars {
                break
            }
            totalChars += charCount
            historyMessages.insert((role: role, content: msg.content), at: 0)
        }

        var messages: [[String: any Sendable]] = [
            ["role": "system", "content": systemContent],
        ]
        for entry in historyMessages {
            messages.append(["role": entry.role, "content": entry.content])
        }
        messages.append(["role": "user", "content": cappedUserTurn])

        return messages
    }
}

// MARK: - AgentChatGraph Callback Helpers

extension AgentChatGraph {
    /// Sets streaming + approval callbacks. Called by coordinator before each run.
    func setCallbacks(
        onToken: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ToolCall) -> Void,
        onApprovalRequired: @escaping @Sendable (UUID, String, String, ToolClearance) async -> ApprovalGate.Decision
    ) {
        onReasoningToken = onToken
        onToolCallDetected = onToolCall
        self.onApprovalRequired = onApprovalRequired
    }

    /// Clears callbacks after graph completes.
    func clearCallbacks() {
        onReasoningToken = nil
        onToolCallDetected = nil
        onApprovalRequired = nil
    }
}
