import AVFoundation
import SwiftUI
import Textual

/// Ephemeral chat message with mutable content for streaming support.
struct EphemeralChatMessage: Identifiable, Equatable {
    let id: UUID
    var content: String
    let isUser: Bool
    var isStreaming: Bool
    let timestamp: Date

    init(content: String, isUser: Bool, isStreaming: Bool = false) {
        id = UUID()
        self.content = content
        self.isUser = isUser
        self.isStreaming = isStreaming
        timestamp = Date()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
    }
}

/// Bottom-centered chat island.
/// Prompt pill at bottom, messages float above with glass backdrop.
struct CommandCenterChatView: View {
    let onDismiss: () -> Void
    let onMessagesChanged: (Bool) -> Void

    @State private var messages: [EphemeralChatMessage] = []
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @State private var copiedMessageID: UUID?
    @State private var savedMessageID: UUID?
    @State private var speakingMessageID: UUID?
    @State private var synthesizer = AVSpeechSynthesizer()
    @FocusState private var isInputFocused: Bool

    private var voiceManager: VoicePushToTalkManager {
        .shared
    }

    private let pillWidth: CGFloat = 740

    var body: some View {
        VStack(spacing: 0) {
            if !messages.isEmpty {
                messagesPanel
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            promptPill
        }
        .frame(width: pillWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: messages.isEmpty)
        .onAppear {
            isInputFocused = true
            voiceManager.onTranscriptReady = { transcript in
                inputText = transcript
                isInputFocused = true
            }
        }
        .onChange(of: voiceManager.partialTranscript) { _, partial in
            if voiceManager.isRecording, !partial.isEmpty {
                inputText = partial
            }
        }
        .onDisappear {
            if voiceManager.isRecording {
                voiceManager.stopListening()
            }
            synthesizer.stopSpeaking(at: .immediate)
        }
        .onChange(of: messages.count) { _, _ in
            onMessagesChanged(!messages.isEmpty)
        }
        // U7: Replaced continuous Timer.publish with onChange-triggered task
        .onChange(of: speakingMessageID) { _, newValue in
            if newValue != nil {
                Task {
                    let deadline = ContinuousClock.now + .seconds(60)
                    while speakingMessageID != nil, synthesizer.isSpeaking {
                        if ContinuousClock.now >= deadline {
                            break
                        }
                        try? await Task.sleep(for: AppConstants.Delays.speechSynthesisPolling)
                    }
                    if speakingMessageID != nil, !synthesizer.isSpeaking {
                        speakingMessageID = nil
                    }
                }
            }
        }
    }

    // MARK: - Messages Panel

    private var messagesPanel: some View {
        VStack(spacing: 0) {
            // Header: New Session + Close
            HStack(spacing: 8) {
                Button {
                    clearSession()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2.weight(.semibold))
                        Text("New")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages) { _, newMessages in
                    if let last = newMessages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: pillWidth)
        .frame(maxHeight: 420)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Message Bubbles

    private func messageBubble(_ message: EphemeralChatMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 120)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                if message.isUser {
                    Text(message.content)
                        .font(AppThemeConstants.chatMessageFont)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppThemeConstants.brandPrimary)
                        )
                } else {
                    markdownContent(message)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }

                if !message.isUser, !message.isStreaming, !message.content.isEmpty {
                    actionButtons(message)
                }
            }

            if !message.isUser {
                Spacer(minLength: 120)
            }
        }
    }

    @ViewBuilder
    private func markdownContent(_ message: EphemeralChatMessage) -> some View {
        let displayText = message.content.isEmpty && message.isStreaming ? "..." : message.content
        StructuredText(markdown: displayText)
            .font(AppThemeConstants.chatMessageFont)
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(.gitHub)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }

    private func actionButtons(_ message: EphemeralChatMessage) -> some View {
        HStack(spacing: 4) {
            Button { copyToClipboard(message) } label: {
                HStack(spacing: 3) {
                    Image(systemName: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                    Text(copiedMessageID == message.id ? "Copied" : "Copy")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(copiedMessageID == message.id ? AppThemeConstants.success : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            Button { saveMessageAsNote(message) } label: {
                HStack(spacing: 3) {
                    Image(systemName: savedMessageID == message.id ? "checkmark" : "square.and.arrow.down")
                        .font(.caption2.weight(.medium))
                    Text(savedMessageID == message.id ? "Saved" : "Save")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(savedMessageID == message.id ? AppThemeConstants.success : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            Button { speakMessage(message) } label: {
                HStack(spacing: 3) {
                    Image(systemName: speakingMessageID == message.id ? "stop.fill" : "speaker.wave.2")
                        .font(.caption2.weight(.medium))
                    Text(speakingMessageID == message.id ? "Stop" : "Speak")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(speakingMessageID == message.id ? AppThemeConstants.error : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
    }

    // MARK: - Prompt Pill

    private var promptPill: some View {
        HStack(alignment: .center, spacing: 12) {
            // App logo
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Input field
            TextField("What can I help you with?", text: $inputText, axis: .vertical)
                .font(.body)
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .lineLimit(1 ... 4)
                .onKeyPress(.return, phases: .down) { _ in
                    if NSEvent.modifierFlags.contains(.shift) {
                        inputText += "\n"
                        return .handled
                    } else if canSend {
                        sendMessage()
                        return .handled
                    }
                    return .handled
                }

            // Mic button
            Button {
                voiceManager.toggle()
            } label: {
                Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(voiceManager.isRecording ? AppThemeConstants.error : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .help(voiceManager.isRecording ? "Stop voice input" : "Voice input")

            // Send / Stop
            if isGenerating {
                Button(action: stopStreaming) {
                    Image(systemName: "stop.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppThemeConstants.error))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSend ? .white : .white.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(canSend ? AppThemeConstants.brandPrimary : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend || LLMEngineStatus.shared.isBusy)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.92)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }

    // MARK: - Logic

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(EphemeralChatMessage(content: text, isUser: true))
        inputText = ""
        isGenerating = true

        // Re-focus input after state update
        Task {
            try? await Task.sleep(for: AppConstants.Delays.focusActivation)
            isInputFocused = true
        }

        let aiMessage = EphemeralChatMessage(content: "", isUser: false, isStreaming: true)
        let aiID = aiMessage.id
        messages.append(aiMessage)

        streamTask = Task { @MainActor in
            do {
                let stream = await LLMEngine.shared.chatStream(prompt: text)
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    if let idx = messages.firstIndex(where: { $0.id == aiID }) {
                        messages[idx].content += chunk
                    }
                }
                if let idx = messages.firstIndex(where: { $0.id == aiID }) {
                    messages[idx].isStreaming = false
                }
                isGenerating = false
                isInputFocused = true
            } catch {
                if !Task.isCancelled {
                    if let idx = messages.firstIndex(where: { $0.id == aiID }) {
                        messages[idx].content = "No AI model loaded. Open Logue and set up a model in Settings \u{2192} Models first."
                        messages[idx].isStreaming = false
                    }
                    isGenerating = false
                    isInputFocused = true
                }
            }
        }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        if let lastIdx = messages.indices.last, messages[lastIdx].isStreaming {
            messages[lastIdx].isStreaming = false
        }
        isGenerating = false
        isInputFocused = true
    }

    private func clearSession() {
        streamTask?.cancel()
        streamTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        speakingMessageID = nil
        messages.removeAll()
        inputText = ""
        isGenerating = false
        isInputFocused = true
    }

    private func speakMessage(_ message: EphemeralChatMessage) {
        if speakingMessageID == message.id {
            synthesizer.stopSpeaking(at: .immediate)
            speakingMessageID = nil
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: message.content)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let voice = AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language.hasPrefix("en") })
            .max(by: { $0.quality.rawValue < $1.quality.rawValue })
        {
            utterance.voice = voice
        }
        speakingMessageID = message.id
        synthesizer.speak(utterance)
    }

    private func saveMessageAsNote(_ message: EphemeralChatMessage) {
        let doc = DocumentStore.shared.createDocument(title: "Chat Note")
        var updated = doc
        updated.body = message.content
        DocumentStore.shared.updateDocument(updated)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        savedMessageID = message.id
        Task {
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            if savedMessageID == message.id {
                savedMessageID = nil
            }
        }
    }

    private func copyToClipboard(_ message: EphemeralChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }
}
