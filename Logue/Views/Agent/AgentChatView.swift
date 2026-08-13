import ImagePlayground
import SwiftUI

/// Full-width detail pane for the agentic AI chat. Provides a ChatGPT-like interface
/// with tool execution cards, conversation history, and quick action prompts.
///
/// Placed in the main content area (not a 320px sidebar panel) to give room for
/// tool execution cards, multi-turn conversations, and workflow progress.
struct AgentChatView: View {
    @State private var coordinator = AgentCoordinator.shared
    @State private var conversationStore = AgentConversationStore.shared
    @State private var inputText = ""
    /// Incremented to pull focus into the input after a card fills it.
    @State private var focusRequest = 0

    // Injected by `MainWindowView`. Read from the environment rather than reaching for
    // the shared singletons again, so this view observes the same instances the rest of
    // the window does.
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(InsightsStatsProvider.self) private var insights
    @Environment(ModelManager.self) private var modelManager
    /// Drag-and-drop attachments staged for the next send. Cleared after each send.
    @State private var inputAttachments: [TempAttachment] = []
    /// When true, the next send routes through `DeepResearchCoordinator` instead
    /// of the regular agent loop. Reset after each run.
    @AppStorage(AppConstants.UserDefaultsKeys.oneShotDeepResearch) private var isDeepResearch: Bool = false
    /// One-shot Web Search toggle for the next send only. Mirrored into
    /// `AgentCoordinator.oneShotIncludeWebTools` at send time and reset right
    /// after, so subsequent regular sends are not affected.
    @AppStorage(AppConstants.UserDefaultsKeys.oneShotWebSearch) private var isWebSearchOnce: Bool = false
    @State private var deepResearchCoordinator = DeepResearchCoordinator.shared
    @State private var showConversationList = false

    // Phase F: Apple Intelligence image generation routing.
    @State private var showImagePlayground = false
    @State private var imagePlaygroundConcept = ""

    /// Shared namespace driving the input-bar geometry transition between the
    /// empty-state center position and the bottom-anchored position.
    @Namespace private var inputBarNamespace

    /// Monotonic counter that increments each time the user sends a message.
    /// Passed to MessageListView to trigger scroll-to-top independently of message count.
    @State private var scrollToTopTrigger = 0

    /// The ID of the user message to scroll to the top.
    @State private var scrollTargetID: UUID?

    /// Observe LLMEngineStatus to disable input when inference is globally busy.
    private var isBusy: Bool {
        LLMEngineStatus.shared.isBusy
    }

    /// The active conversation (auto-creates one if none exists).
    private var activeConversation: AgentConversation? {
        if let id = conversationStore.selectedConversationID {
            return conversationStore.conversations.first { $0.id == id }
        }
        return nil
    }

    /// True when the active conversation already has at least one message.
    /// Drives the layout branch: pre-conversation = centered hero, post = bottom bar.
    private var hasMessages: Bool {
        guard let conversation = activeConversation else { return false }
        return !conversation.messages.isEmpty
    }

    @State private var canvas = CanvasController.shared
    /// Sources panel auto-managed by the active conversation: opens when the
    /// agent emits sourced answers (web tools, meeting/document references),
    /// closes when the user switches conversations or starts a new chat.
    /// The toolbar button still acts as a manual override.
    @State private var showSourcesPanel = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if hasMessages, let conversation = activeConversation {
                    hasMessagesLayout(conversation: conversation)
                } else {
                    landingLayout
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.spring, value: hasMessages)

            if !canvas.snapshots.isEmpty {
                Divider()
                CanvasPaneView()
                    .frame(minWidth: 380, idealWidth: 480, maxWidth: .infinity)
                    .animation(Motion.spring, value: canvas.snapshots.count)
            } else if showSourcesPanel, hasAnswerSources {
                // Both conditions, not just the toggle. `showSourcesPanel` is the user's
                // preference; `hasAnswerSources` is whether there is anything to show. On
                // Home — and in any conversation the agent has not sourced — the answer is
                // no, and a panel that opens onto nothing is a dead half of the window.
                Divider()
                SourcesPanelView(
                    conversationID: AgentConversationStore.shared.selectedConversationID,
                    attachments: $inputAttachments
                )
            }
        }
        // The landing state is Home, whatever the auto-created conversation happens to
        // be called — titling an empty screen "New Conversation" names a thread the user
        // has not started yet. The conversation's own title takes over once it has one.
        .navigationTitle(hasMessages ? (activeConversation?.title ?? "Home") : "Home")
        .navigationSubtitle(topBarSubtitle)
        .toolbar { chatToolbar }
        .toastOverlay()
        // Phase F: ImagePlayground sheet — invoked when intent classifier fires (score ≥ 0.70).
        // The completion delivers a file URL to the generated image; we copy it as a TempAttachment
        // and inject a note into the conversation so it persists in the thread.
        .imagePlaygroundSheet(isPresented: $showImagePlayground, concept: imagePlaygroundConcept) { imageURL in
            guard let conversationID = AgentConversationStore.shared.selectedConversationID else { return }
            let attachment = TempAttachment(
                kind: .image,
                displayName: imageURL.lastPathComponent,
                extractedText: "",
                iconName: "photo"
            )
            let msg = AgentMessage(
                role: .assistant,
                content: "Generated with Apple ImagePlayground. Tap and hold to save.",
                attachments: [attachment]
            )
            AgentConversationStore.shared.appendMessage(msg, to: conversationID)
        }
        .onAppear {
            ensureActiveConversation()
            showSourcesPanel = hasAnswerSources
        }
        .onChange(of: activeConversation?.messages.last?.content) { _, content in
            // Phase C: open Canvas automatically for long code or
            // preview-eligible languages on the latest assistant turn.
            guard activeConversation?.messages.last?.role == .assistant,
                  let content,
                  let opener = CanvasController.shouldOpenForResponse(content),
                  opener.open
            else { return }
            // Avoid duplicating the same content on streaming flicker.
            if canvas.snapshots.last?.content == opener.content {
                return
            }
            canvas.push(content: opener.content, language: opener.language)
        }
        .onChange(of: activeConversation?.id) { _, _ in
            // Switching conversations (or starting a new one) hides the panel.
            withAnimation(Motion.spring) { showSourcesPanel = false }
        }
        .onChange(of: hasAnswerSources) { _, has in
            // Auto-open the panel as soon as the agent emits sourced output;
            // never auto-close mid-conversation since the user may have
            // closed it intentionally — only the conversation-id change does.
            if has {
                withAnimation(Motion.spring) { showSourcesPanel = true }
            }
        }
    }

    /// Does the active conversation contain any answer-derived sources?
    /// Drives the right-pane auto-open behavior. Considers web tool calls and
    /// meeting/document references — the same surfaces SourcesPanelView renders.
    private var hasAnswerSources: Bool {
        guard let conversation = activeConversation else { return false }
        for msg in conversation.messages {
            for call in msg.toolCalls {
                let name = call.toolName.lowercased()
                if name.contains("web") || name.contains("search") || name.contains("fetch")
                    || name.contains("meeting") || name.contains("document")
                {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Layouts

    /// Pre-conversation layout: greeting and chips, the prompt bar, then the dashboard
    /// cards. The prompt bar is pinned between the two rather than living inside the
    /// card scroll view — see `HomeLandingView` for why that matters to the geometry
    /// match that slides it to the bottom on first send.
    private var landingLayout: some View {
        VStack(spacing: 0) {
            HomeLandingHeader(chips: suggestionChips, onPrefill: prefill)

            if modelManager.activeModelID == nil {
                Label("Set up a model to ask Logue", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(AppThemeConstants.warning)
                    .padding(.horizontal, AppThemeConstants.paddingXXLarge)
                    .padding(.top, AppThemeConstants.paddingMedium)
            }

            inputBar
                .matchedGeometryEffect(id: "inputBar", in: inputBarNamespace)
                .frame(maxWidth: AppThemeConstants.contentColumnWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppThemeConstants.paddingXXLarge)
                .padding(.vertical, AppThemeConstants.paddingLarge)

            HomeLandingView(onPrefill: prefill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Puts a sentence in the input without sending it. A card that asks the question
    /// for the user still leaves them the last word on it.
    private func prefill(_ text: String) {
        inputText = text
        focusRequest += 1
    }

    /// Derived fresh each render from the stores — no inference, no caching. The rules
    /// live in `HomeSuggestions` so they can be tested without a view.
    private var suggestionChips: [HomeSuggestions.Chip] {
        let calendar = Calendar.current
        let unsummarized = meetingStore.activeMeetings
            .filter { ($0.summary ?? "").isEmpty && !$0.isArchived }
            .max { $0.createdAt < $1.createdAt }
        return HomeSuggestions.chips(
            for: HomeSuggestions.Inputs(
                unsummarizedMeetingTitle: unsummarized?.title,
                overdueCount: insights.actionItemStats.overdue,
                meetingsToday: meetingStore.activeMeetings.filter {
                    calendar.isDateInToday($0.createdAt) && !$0.isArchived
                }.count,
                hasAnyContent: !(documentStore.activeDocuments.isEmpty
                    && meetingStore.activeMeetings.isEmpty)
            )
        )
    }

    /// Post-first-message layout: scrolling message list + bottom-anchored input
    /// bar. Same `inputBar` view, same namespace — `matchedGeometryEffect` handles
    /// the slide-down animation when the user sends their first message.
    @ViewBuilder
    private func hasMessagesLayout(conversation: AgentConversation) -> some View {
        MessageListView(
            messages: conversation.messages,
            activeToolCalls: coordinator.activeToolCalls,
            isProcessing: coordinator.isProcessing,
            isStreaming: coordinator.isStreaming,
            streamingText: coordinator.streamingText,
            conversationID: conversation.id,
            scrollToTopTrigger: scrollToTopTrigger,
            scrollTargetID: scrollTargetID,
            onRegenerateFromUserMessage: { messageID, newContent in
                regenerateFromEditedMessage(
                    messageID: messageID,
                    newContent: newContent,
                    conversationID: conversation.id
                )
            }
        )

        if let error = coordinator.lastError {
            errorBanner(error)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        DeepResearchProgressView()

        inputBar
            .matchedGeometryEffect(id: "inputBar", in: inputBarNamespace)
            .frame(maxWidth: AppThemeConstants.contentColumnWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }

    // MARK: - Input Bar (shared between layouts)

    /// The single source of truth for the input bar view. Both `emptyLayout` and
    /// `hasMessagesLayout` render this through `matchedGeometryEffect` so the
    /// transition between center and bottom positions interpolates smoothly.
    private var inputBar: some View {
        InputBarView(
            inputText: $inputText,
            focusRequest: $focusRequest,
            attachments: $inputAttachments,
            isProcessing: coordinator.isProcessing || deepResearchCoordinator.isRunning,
            isBusy: isBusy,
            onSend: {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                let attachments = inputAttachments
                let runDeepResearch = isDeepResearch
                let oneShotWeb = isWebSearchOnce
                // Allow attachment-only sends so the user can drop a file and ask
                // the agent to read it without typing a question.
                guard !text.isEmpty || !attachments.isEmpty else { return }
                inputText = ""
                inputAttachments = []
                // Reset the per-send AppStorage flags so the next turn starts
                // clean. These mirror the chip state in the input pill.
                isDeepResearch = false
                isWebSearchOnce = false
                if runDeepResearch {
                    startDeepResearch(text, oneShotWebSearch: oneShotWeb)
                } else {
                    sendMessage(text, attachments: attachments, oneShotWebSearch: oneShotWeb)
                }
            },
            onCancel: {
                if deepResearchCoordinator.isRunning {
                    deepResearchCoordinator.cancel()
                } else {
                    coordinator.cancel()
                }
            }
        )
        .disabled(isBusy && !coordinator.isProcessing)
    }

    // MARK: - Window Toolbar

    /// Items injected into the macOS window titlebar. The chat title +
    /// subtitle render via `.navigationTitle` / `.navigationSubtitle`; this
    /// toolbar only owns the trailing controls.
    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showConversationList.toggle()
            } label: {
                Image(systemName: "clock")
            }
            .help("Conversation history")
            .popover(isPresented: $showConversationList, arrowEdge: .bottom) {
                AgentConversationListView { selectedID in
                    conversationStore.selectedConversationID = selectedID
                    showConversationList = false
                }
                .frame(width: 320, height: 400)
            }

            Button {
                let conv = conversationStore.createConversation()
                conversationStore.selectedConversationID = conv.id
                inputText = ""
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("New conversation")

            // Only offered once the agent has actually cited something. A toggle that is
            // always present on Home advertises a panel with nothing in it, and pressing
            // it is a dead end rather than a feature.
            if hasAnswerSources {
                Button {
                    showSourcesPanel.toggle()
                } label: {
                    Image(systemName: showSourcesPanel ? "sidebar.right" : "sidebar.squares.right")
                        .foregroundStyle(showSourcesPanel ? Color.accentColor : Color.primary)
                }
                .help(showSourcesPanel ? "Hide sources panel" : "Show sources panel")
            }
        }
    }

    private var topBarSubtitle: String {
        let messageCount = activeConversation?.messages.count ?? 0
        if coordinator.isStreaming || coordinator.isProcessing {
            // Vary the subtitle by the active tool so users see what the
            // agent is actually doing, not a static "Thinking…".
            let activeTool = coordinator.activeToolCalls.last?.toolName
            return UICopy.Status.describe(toolName: activeTool)
        }
        if messageCount == 0 {
            return UICopy.Trust.bannerFull
        }
        return "\(messageCount) message\(messageCount == 1 ? "" : "s")"
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(UICopy.Error.modelUnreachable)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                withAnimation {
                    coordinator.dismissError()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AppThemeConstants.error.opacity(AppThemeConstants.opacityLight),
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .strokeBorder(AppThemeConstants.error.opacity(AppThemeConstants.opacityMedium), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Actions

    private func sendMessage(
        _ text: String,
        attachments: [TempAttachment] = [],
        oneShotWebSearch: Bool = false
    ) {
        // Phase F: Route to ImagePlayground when intent classifier fires.
        if attachments.isEmpty, PromptIntentClassifier.shared.shouldPresentImagePlayground(for: text) {
            HapticFeedback.send()
            imagePlaygroundConcept = text
            showImagePlayground = true
            return
        }

        HapticFeedback.send()
        let conversationID = ensureActiveConversation()

        // Pre-create the user message so we know its ID for scrolling. Attachments
        // ride along on the message so they survive a re-render and persist with
        // the conversation.
        let userMsg = AgentMessage(role: .user, content: text, attachments: attachments)
        AgentConversationStore.shared.appendMessage(userMsg, to: conversationID)

        // Set the scroll target BEFORE the coordinator starts adding placeholders
        scrollTargetID = userMsg.id
        scrollToTopTrigger += 1

        // Start the agent loop (skipping user message append since we did it here).
        // The coordinator picks up the attachments from the appended message in
        // `runGraph` so we don't need to pass them again here.
        coordinator.sendWithoutAppendingUser(
            conversationID: conversationID,
            oneShotWebSearch: oneShotWebSearch
        )
    }

    /// Routes a user message through the Deep Research pipeline instead of the
    /// regular agent loop. Appends the user message + kicks off the coordinator;
    /// the coordinator posts a clarification, report, or failure message when it
    /// finishes.
    private func startDeepResearch(_ text: String, oneShotWebSearch: Bool = false) {
        HapticFeedback.send()
        let conversationID = ensureActiveConversation()
        let userMsg = AgentMessage(role: .user, content: text)
        AgentConversationStore.shared.appendMessage(userMsg, to: conversationID)
        scrollTargetID = userMsg.id
        scrollToTopTrigger += 1
        deepResearchCoordinator.run(
            prompt: text,
            conversationID: conversationID,
            oneShotWebSearch: oneShotWebSearch
        )
    }

    private func regenerateFromEditedMessage(messageID: UUID, newContent: String, conversationID: UUID) {
        // Set the scroll target so the edited message jumps to the top, matching sendMessage().
        scrollTargetID = messageID
        scrollToTopTrigger += 1
        coordinator.regenerateFromUserMessage(
            messageID: messageID,
            in: conversationID,
            newContent: newContent
        )
    }

    @discardableResult
    private func ensureActiveConversation() -> UUID {
        if let id = conversationStore.selectedConversationID,
           conversationStore.conversations.contains(where: { $0.id == id })
        {
            return id
        }
        let conv = conversationStore.createConversation()
        return conv.id
    }
}
