import AppKit
import SwiftUI

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var content: String
    /// True for assistant messages that contain multi-paragraph drafted content
    /// (heuristic: ≥ 3 newlines and ≥ 100 chars). Shows Insert + Copy actions.
    var isInsertable: Bool = false
    /// Selected text that was attached via "Ask AI". Shown as a quote in the chat bubble.
    var quotedContext: String?

    init(role: ChatRole, content: String, quotedContext: String? = nil) {
        id = UUID()
        self.role = role
        self.content = content
        self.quotedContext = quotedContext
    }

    enum ChatRole: String, Codable { case user, assistant }
}

// MARK: - AIChatPanelView

/// AI Assistant tool panel — conversational assistant for the current document.
struct AIChatPanelView: View {
    let document: WritingDocument
    var onSave: (() -> Void)?
    @Binding var messages: [ChatMessage]
    @Binding var pendingMessage: String?
    let onInsert: (String) -> Void

    @State private var inputText = ""
    @State private var isTyping = false
    @State private var streamTask: Task<Void, Never>?
    @State private var inputHeight: CGFloat = 20
    @State private var voiceManager = VoicePushToTalkManager.shared
    @State private var scrollToBottom: UUID?
    /// Selected text from "Ask AI" — shown as a context card above the input bar.
    @State private var contextSelection: String?
    /// Triggers focus on the input field when "Ask AI" sets a pending message.
    @State private var focusInput = false

    var body: some View {
        VStack(spacing: 0) {
            if !messages.isEmpty {
                clearChatBar
            }
            if messages.isEmpty {
                emptyState
            } else {
                messageList
            }
            Divider()
            chatInput
        }
        .background(AppThemeConstants.surfaceBackground)
        .onAppear {
            if let pending = pendingMessage {
                pendingMessage = nil
                contextSelection = pending
                inputText = "Please help me improve or analyse this text."
                focusInput = true
            }
        }
        .onChange(of: pendingMessage) { _, newValue in
            guard let pending = newValue else { return }
            pendingMessage = nil
            contextSelection = pending
            inputText = "Please help me improve or analyse this text."
            focusInput = true
        }
    }

    // MARK: - Clear Chat Bar

    private var clearChatBar: some View {
        HStack {
            Spacer()
            Button {
                messages.removeAll()
                onSave?()
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear chat")
            .accessibilityLabel("Clear chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppThemeConstants.accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title2)
                    .foregroundStyle(AppThemeConstants.accent)
            }

            VStack(spacing: 4) {
                Text("How can I help?")
                    .font(.headline)
                Text("Ask me anything about your writing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Ideas for you")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    if document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        QuickPromptChip(label: "Help me brainstorm", icon: "brain") {
                            sendMessage("Help me brainstorm ideas for what to write about.")
                        }
                        QuickPromptChip(label: "Create an outline", icon: "list.bullet.rectangle") {
                            sendMessage("Help me create a structured outline for my document.")
                        }
                        QuickPromptChip(label: "Write a first draft", icon: "pencil.line") {
                            sendMessage("Help me write a first draft. What topic should we start with?")
                        }
                        QuickPromptChip(label: "Writing tips", icon: "lightbulb") {
                            sendMessage("Give me some tips for writing effectively.")
                        }
                    } else {
                        QuickPromptChip(label: "Improve my writing", icon: "wand.and.stars") {
                            sendMessage("Please review and suggest improvements for my writing in this document.")
                        }
                        QuickPromptChip(label: "Fix grammar", icon: "checkmark.shield") {
                            sendMessage("Please identify and fix all grammar and spelling issues in the document.")
                        }
                        QuickPromptChip(label: "Make it concise", icon: "arrow.down.to.line.compact") {
                            sendMessage("Please make the writing more concise without losing meaning.")
                        }
                        QuickPromptChip(label: "Change tone", icon: "speaker.wave.2") {
                            sendMessage("Please adjust the tone of my writing to be more appropriate for the intended audience.")
                        }
                        QuickPromptChip(label: "Summarize", icon: "text.justify.left") {
                            sendMessage("Please provide a brief summary of this document.")
                        }
                        QuickPromptChip(label: "Expand ideas", icon: "arrow.up.left.and.arrow.down.right") {
                            sendMessage("Please help me expand and develop the ideas in this document further.")
                        }
                        QuickPromptChip(label: "Add examples", icon: "lightbulb") {
                            sendMessage("Please suggest relevant examples I could add to strengthen my writing.")
                        }
                        QuickPromptChip(label: "Simplify language", icon: "text.redaction") {
                            sendMessage("Please simplify the language to make it easier to understand.")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        if !(msg.role == .assistant && msg.content.isEmpty) {
                            ChatBubble(
                                message: msg,
                                onInsert: msg.isInsertable ? { onInsert(msg.content) } : nil,
                                onCopy: msg.role == .assistant ? {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(msg.content, forType: .string)
                                } : nil
                            )
                            .id(msg.id)
                        }
                    }
                    if isTyping, messages.last?.content.isEmpty ?? true {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(AppThemeConstants.paddingMedium)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isTyping) {
                if isTyping {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
            .onChange(of: scrollToBottom) {
                if let id = scrollToBottom {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Context Selection Card

    private var contextSelectionCard: some View {
        HStack(alignment: .top, spacing: 8) {
            // Accent bar sized to match text content height
            AppThemeConstants.accent
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(contextSelection ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    contextSelection = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove selected text context")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppThemeConstants.accent.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Chat Input

    private var chatInput: some View {
        VStack(spacing: 0) {
            if contextSelection != nil {
                contextSelectionCard
            }

            if voiceManager.isRecording {
                VoiceInputIndicator(
                    audioLevel: voiceManager.audioLevel,
                    partialTranscript: voiceManager.partialTranscript,
                    onStop: { voiceManager.stopListening() }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 8) {
                ChatInputField(text: $inputText, height: $inputHeight, onSubmit: submit, requestFocus: $focusInput)
                    .frame(height: inputHeight)

                // Mic button for voice input
                Button {
                    voiceManager.toggle()
                } label: {
                    Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(voiceManager.isRecording ? AppThemeConstants.error : .secondary)
                }
                .buttonStyle(.plain)
                .help(voiceManager.isRecording ? "Stop voice input" : "Voice input")
                .accessibilityLabel(voiceManager.isRecording ? "Stop voice input" : "Start voice input")

                if isTyping {
                    Button(action: stopGeneration) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppThemeConstants.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating")
                    .accessibilityLabel("Stop generating")
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.5) : AppThemeConstants.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || LLMEngineStatus.shared.isBusy)
                    .help("Send message")
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(Color.primary.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(AppThemeConstants.chromeBackground)
        .onAppear {
            voiceManager.onTranscriptReady = { transcript in
                inputText = transcript
            }
        }
        .onDisappear {
            // B3: Cancel streaming task on view disappear
            streamTask?.cancel()
            streamTask = nil
            isTyping = false
            voiceManager.onTranscriptReady = nil
            if voiceManager.isRecording {
                voiceManager.stopListening()
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let selection = contextSelection {
            // Show clean question + quote in chat, send context with XML tags only to LLM
            let llmPrompt = "About this text:\n<content>\n\(selection)\n</content>\n\n\(text)"
            sendMessageWithContext(displayText: text, quotedContext: selection, llmPrompt: llmPrompt)
            contextSelection = nil
        } else {
            sendMessage(text)
        }
    }

    // B1: Use message UUID instead of positional index to prevent out-of-bounds crash
    private func sendMessage(_ text: String) {
        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))

        let assistantMsg = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMsg)
        let assistantMsgID = assistantMsg.id
        isTyping = true

        streamTask = Task { @MainActor in
            do {
                try await streamResponse(for: text, messageID: assistantMsgID)
            } catch {
                handleStreamError(error, messageID: assistantMsgID)
            }
            isTyping = false
            streamTask = nil
            onSave?()
        }
    }

    /// Sends a message where the user-visible text differs from the LLM prompt.
    /// Used by "Ask AI" to keep XML tags out of the chat bubble.
    private func sendMessageWithContext(displayText: String, quotedContext: String, llmPrompt: String) {
        inputText = ""
        messages.append(ChatMessage(role: .user, content: displayText, quotedContext: quotedContext))

        let assistantMsg = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMsg)
        let assistantMsgID = assistantMsg.id
        isTyping = true

        streamTask = Task { @MainActor in
            do {
                try await streamResponse(for: llmPrompt, messageID: assistantMsgID)
            } catch {
                handleStreamError(error, messageID: assistantMsgID)
            }
            isTyping = false
            streamTask = nil
            onSave?()
        }
    }

    private func streamResponse(for text: String, messageID: UUID) async throws {
        let context = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Truncate document content to fit context window
        let maxChars = LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.summaryReservedTokens)
        let safeContext = String(context.prefix(maxChars))
        let fullPrompt = safeContext.isEmpty
            ? text
            : "\(text)\n\n---\n\nDOCUMENT CONTENT:\n<content>\n\(safeContext)\n</content>"
        let system = PromptRegistry.Meeting.documentChatSystem.content
        let stream = await LLMEngine.shared.completeStream(system: system, prompt: fullPrompt, maxTokens: 2048)
        var tokenCount = 0
        for try await token in stream {
            guard !Task.isCancelled else { break }
            guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { break }
            messages[idx].content += token
            tokenCount += 1
            if tokenCount % 4 == 0 {
                scrollToBottom = messageID
            }
        }
        scrollToBottom = messageID
        if let idx = messages.firstIndex(where: { $0.id == messageID }) {
            messages[idx].isInsertable = looksLikeDraftContent(messages[idx].content)
        }
    }

    private func handleStreamError(_ error: Error, messageID: UUID) {
        guard !Task.isCancelled else { return }
        let errorText = if let engineErr = error as? LLMError {
            engineErr.localizedDescription
        } else {
            "Something went wrong: \(error.localizedDescription)"
        }
        if let idx = messages.firstIndex(where: { $0.id == messageID }),
           messages[idx].content.isEmpty
        {
            messages[idx].content = errorText
        }
    }

    private func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isTyping = false
        onSave?()
    }

    /// Heuristic: multi-paragraph response (≥3 newlines, ≥100 chars) is likely drafted content.
    private func looksLikeDraftContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newlineCount = trimmed.components(separatedBy: "\n").count - 1
        return trimmed.count >= 100 && newlineCount >= 3
    }
}
