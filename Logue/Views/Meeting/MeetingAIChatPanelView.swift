import AppKit
import SwiftUI

/// Right panel for asking AI questions about the meeting transcript.
/// UI unified with AIChatPanelView — uses ChatBubble, ChatInputField, TypingIndicatorView.
struct MeetingAIChatPanelView: View {
    let meeting: MeetingNote
    var onSave: (() -> Void)?

    @Binding var messages: [MeetingChatMessage]
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var streamTask: Task<Void, Never>?
    @State private var inputHeight: CGFloat = 20
    @State private var voiceManager = VoicePushToTalkManager.shared
    @State private var scrollToBottom: UUID?
    @Environment(RecordingSessionManager.self) private var recorder

    /// Meeting Q&A system prompt, sourced from `PromptRegistry.Meeting.meetingChatSystem`.
    private static let chatSystem = PromptRegistry.Meeting.meetingChatSystem.content

    var body: some View {
        VStack(spacing: 0) {
            if !messages.isEmpty {
                clearChatBar
            }

            if messages.isEmpty, meeting.segments.isEmpty, !recorder.isRecording, !recorder.isStartingRecording {
                EmptyStateView(
                    icon: "sparkles",
                    title: "Record a meeting first",
                    description: "Once you have a transcript, you can ask questions about what was discussed.",
                    actionLabel: "Start Meeting",
                    action: {
                        Task { await recorder.startRecording(for: meeting) }
                    }
                )
            } else if messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()
            chatInput
        }
        .background(AppThemeConstants.surfaceBackground)
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
            Spacer()

            ZStack {
                Circle()
                    .fill(AppThemeConstants.accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title2)
                    .foregroundStyle(AppThemeConstants.accent)
            }

            VStack(spacing: 4) {
                Text("Ask about this meeting")
                    .font(.headline)
                Text("Ask questions about what was discussed.")
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
                    QuickPromptChip(label: "Key decisions", icon: "checkmark.seal") {
                        sendMessage("What were the key decisions?")
                    }
                    QuickPromptChip(label: "Action items", icon: "checklist") {
                        sendMessage("List all action items")
                    }
                    QuickPromptChip(label: "Summarize", icon: "text.justify.left") {
                        sendMessage("Summarize this meeting in 3 bullet points")
                    }
                    QuickPromptChip(label: "Follow-ups", icon: "arrow.uturn.forward") {
                        sendMessage("What topics need follow-up from this meeting?")
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        if !(message.role == .assistant && message.content.isEmpty) {
                            MeetingChatBubble(
                                message: message,
                                onCopy: message.role == .assistant ? {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.content, forType: .string)
                                } : nil
                            )
                            .id(message.id)
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

    // MARK: - Chat Input

    private var chatInput: some View {
        VStack(spacing: 0) {
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
                ChatInputField(text: $inputText, height: $inputHeight, onSubmit: submit, requestFocus: .constant(false))
                    .frame(height: inputHeight)

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
                            .foregroundStyle(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.5) : AppThemeConstants.accent
                            )
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
        sendMessage(text)
    }

    // MARK: - Send Message (Streaming)

    // B1: Use message UUID instead of positional index to prevent out-of-bounds crash
    // swiftlint:disable:next function_body_length
    private func sendMessage(_ text: String) {
        inputText = ""
        messages.append(MeetingChatMessage(role: .user, content: text))

        let assistantMsg = MeetingChatMessage(role: .assistant, content: "")
        messages.append(assistantMsg)
        let assistantMsgID = assistantMsg.id
        isTyping = true

        streamTask = Task { @MainActor in
            do {
                let crossContext: String? = if MeetingPromptBuilder.referencesPastMeetings(text) {
                    await MeetingMemoryIndex.shared.buildCrossMeetingContext(
                        for: text,
                        currentMeetingID: meeting.id,
                        meetings: MeetingStore.shared.activeMeetings
                    )
                } else {
                    nil
                }

                // Truncate transcript to fit context window (~4 chars/token, reserve tokens for output + system prompt)
                let maxChatChars = LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.summaryReservedTokens)
                let safeTranscript = String(meeting.fullTranscript.prefix(maxChatChars))

                let prompt = MeetingPromptBuilder.buildChatPrompt(
                    question: text,
                    transcript: safeTranscript,
                    summary: meeting.summary,
                    actionItems: meeting.actionItems,
                    crossMeetingContext: crossContext
                )

                if crossContext != nil {}

                let stream = await LLMEngine.shared.completeStream(
                    system: Self.chatSystem,
                    prompt: prompt,
                    maxTokens: 2048
                )
                var tokenCount = 0
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    guard let idx = messages.firstIndex(where: { $0.id == assistantMsgID }) else { break }
                    messages[idx].content += token
                    tokenCount += 1
                    if tokenCount % 4 == 0 {
                        scrollToBottom = assistantMsgID
                    }
                }
                scrollToBottom = assistantMsgID
                isTyping = false
                streamTask = nil
                onSave?()
            } catch {
                if !Task.isCancelled,
                   let idx = messages.firstIndex(where: { $0.id == assistantMsgID }),
                   messages[idx].content.isEmpty
                {
                    let errorText: String = if let engineErr = error as? LLMError {
                        engineErr.localizedDescription
                    } else {
                        "Something went wrong: \(error.localizedDescription)"
                    }
                    messages[idx].content = errorText
                }
                isTyping = false
                streamTask = nil
                onSave?()
            }
        }
    }

    private func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isTyping = false
        onSave?()
    }
}

// MARK: - Supporting Types

struct MeetingChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String

    init(role: Role, content: String) {
        id = UUID()
        self.role = role
        self.content = content
    }

    enum Role: String, Codable {
        case user
        case assistant
    }
}

// MARK: - Meeting Chat Bubble (unified with ChatBubble styling)

private struct MeetingChatBubble: View {
    let message: MeetingChatMessage
    var onCopy: (() -> Void)?

    @State private var isHovered = false
    @State private var copiedFeedback = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Group {
                if message.role == .assistant {
                    MarkdownTextView(text: message.content)
                } else {
                    Text(message.content)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                    ? AppThemeConstants.brandPrimary
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
            )
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            .textSelection(.enabled)

            if message.role == .assistant, let copyAction = onCopy {
                HStack(spacing: 8) {
                    Button {
                        copyAction()
                        withAnimation(.easeInOut(duration: 0.2)) { copiedFeedback = true }
                        Task {
                            try? await Task.sleep(for: AppConstants.Delays.clipboardFeedback)
                            withAnimation { copiedFeedback = false }
                        }
                    } label: {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .padding(6)
                            .background(
                                copiedFeedback ? AppThemeConstants.success.opacity(0.12) : AppThemeConstants.quaternaryFill,
                                in: RoundedRectangle(
                                    cornerRadius: AppThemeConstants.radiusSmall,
                                    style: .continuous
                                )
                            )
                            .foregroundStyle(copiedFeedback ? AppThemeConstants.success : .secondary)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: copiedFeedback)
                    .help(copiedFeedback ? "Copied!" : "Copy to clipboard")
                }
                .opacity(isHovered || copiedFeedback ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
