import AVFoundation
import SwiftUI
import Textual

/// Bottom-centered chat island.
/// Prompt pill at bottom, messages float above with glass backdrop.
struct CommandCenterChatView: View {
    let onDismiss: () -> Void
    let onContentChanged: (CommandCenterChatContent) -> Void

    /// The island's own thread, created on first send and never selected.
    ///
    /// Created with `select: false`: this floats over another app, and selecting its thread
    /// would navigate the main window sitting behind it away from whatever the user left open.
    @State private var conversationID: UUID?
    @State private var store = AgentConversationStore.shared
    @State private var coordinator = AgentCoordinator.shared
    // Extension-visible: +Composer
    @State var inputText: String = ""
    // Extension-visible: +Composer
    /// Files staged for the next send. The island could not accept any until the intake was
    /// lifted out of the main window's input bar — see `AttachmentIntake`.
    @State var attachments: [TempAttachment] = []
    // Extension-visible: +Composer
    /// Web search for the next send, belonging to this island alone.
    ///
    /// It used to bind the same `UserDefaults` key as the main window's chip, on the reasoning
    /// that one value with several readers beats a copy per surface. That was wrong in the
    /// direction nobody checked: the island clears the flag after every send, so asking a
    /// quick question here silently disarmed a Search chip the user had turned on in the main
    /// window and left armed on an unsent prompt. They would never be told — the prompt just
    /// runs without web tools.
    ///
    /// The coordinator takes the value as a parameter, so nothing needs the shared read. A
    /// per-send mode is per surface, and this is `@State` accordingly.
    @State var isWebSearchOnce: Bool = false
    // Extension-visible: +Composer
    /// Deep Research for the next send, belonging to this island alone.
    ///
    /// Same story as the web-search flag above, and the same fix: this bound the key the main
    /// window's Deep Research toggle binds, and the island clears it after every send — so a
    /// question asked here disarmed a Deep Research run the user had set up over there. The
    /// consequence is larger than the search one, because that run is the expensive one they
    /// deliberately chose.
    @State var isDeepResearchOnce: Bool = false
    // Extension-visible: +Composer
    @State var deepResearch = DeepResearchCoordinator.shared
    // Extension-visible: +Bubbles
    @State var copiedMessageID: UUID?
    // Extension-visible: +Bubbles
    @State var savedMessageID: UUID?
    // Extension-visible: +Bubbles
    @State var speakingMessageID: UUID?
    @State private var synthesizer = AVSpeechSynthesizer()
    // Extension-visible: +Composer
    @FocusState var isInputFocused: Bool

    // Extension-visible: +Composer
    var voiceManager: VoicePushToTalkManager {
        .shared
    }

    /// The island's thread as stored.
    ///
    /// Read from the store rather than held here. That is the whole point of the change: the
    /// island used to keep its own array and throw it away on dismiss, so a question asked
    /// here had no history, no tools and no memory. It is now the same conversation the rest
    /// of Logue can see.
    private var storedMessages: [AgentMessage] {
        guard let conversationID,
              let conversation = store.conversations.first(where: { $0.id == conversationID })
        else { return [] }
        return conversation.messages
    }

    /// What the island draws: the turns, and the work the agent did between them.
    private var rows: [IslandRow] {
        guard let conversationID else { return [] }
        return IslandThread.rows(
            for: storedMessages,
            isStreaming: coordinator.isStreaming(in: conversationID)
        )
    }

    /// Whether there is anything in the thread at all — the pill stands alone until there is.
    private var hasContent: Bool {
        !rows.isEmpty
    }

    // Extension-visible: +Composer
    /// Whether the island's own thread is busy — never the main window's.
    var isGenerating: Bool {
        guard let conversationID else { return false }
        return coordinator.isProcessing(in: conversationID)
            || deepResearch.isRunning(in: conversationID)
    }

    private let pillWidth: CGFloat = 740

    private var content: CommandCenterChatContent {
        CommandCenterChatContent(
            hasMessages: hasContent,
            hasDraft: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasAttachments: !attachments.isEmpty
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasContent {
                messagesPanel
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            promptPill
        }
        .frame(width: pillWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hasContent)
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
        .onChange(of: rows.count) { _, _ in
            onContentChanged(content)
        }
        // Staged files count as content, so the controller has to be told about them —
        // without this the island reports itself empty while holding a PDF, and the next
        // click anywhere off the pill throws it away.
        .onChange(of: attachments.count) { _, _ in
            onContentChanged(content)
        }
        .onChange(of: inputText) { _, _ in
            onContentChanged(content)
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

                if conversationID != nil {
                    Button {
                        openInLogue()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward")
                                .font(.caption2.weight(.semibold))
                            Text("Open in Logue")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Continue this conversation in the main window")
                }

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
                        ForEach(rows) { row in
                            islandRow(row)
                                .id(row.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChange(of: rows) { _, newRows in
                    if let last = newRows.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if !pendingApprovals.isEmpty, let conversationID {
                VStack(spacing: 8) {
                    ForEach(pendingApprovals) { call in
                        ToolExecutionCard(
                            toolCall: call,
                            result: nil,
                            conversationID: conversationID
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Mounted, not redrawn: the island shows the same seven-step strip the main
            // window does, scoped to its own thread so a run started over there stays over
            // there.
            DeepResearchProgressView(conversationID: conversationID)

            if let error = currentError {
                errorBanner(error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    // MARK: - Logic

    // Extension-visible: +Composer
    var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && !isGenerating
    }

    // Extension-visible: +Composer
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // The same routing decision the main window makes, on the same inputs. Every one of
        // them is now reachable from here, so the island asks the one router and gets the one
        // answer rather than carrying a second opinion that can drift from it.
        let route = AskRouter.route(
            for: AskRouter.Request(
                text: text,
                hasAttachments: !attachments.isEmpty,
                deepResearchRequested: isDeepResearchOnce,
                imageIntentFires: PromptIntentClassifier.shared.shouldPresentImagePlayground(for: text)
            )
        )
        guard let route, !isGenerating else { return }

        // `isGenerating` is scoped to this conversation, which is right for the spinner and
        // wrong for this: `AgentCoordinator.send` refuses on a *global* busy check. Without
        // this guard a send made while the main window was mid-run cleared the field, the
        // staged files and the mode flags, then hit that refusal and did nothing — no bubble,
        // no error, and an empty conversation left behind by `ensureConversation`.
        guard !coordinator.isProcessingAnyConversation else {
            ToastCenter.shared.show(UICopy.Status.busyElsewhere, kind: .warning)
            return
        }

        let conversationID = ensureConversation()
        let staged = attachments
        let searchThisTurn = isWebSearchOnce
        inputText = ""
        attachments = []
        // Cleared per send, like the main window's chips. Left set, a mode switched on here
        // would arm the next send in the other window too.
        isWebSearchOnce = false
        isDeepResearchOnce = false

        // Re-focus input after state update
        Task {
            try? await Task.sleep(for: AppConstants.Delays.focusActivation)
            isInputFocused = true
        }

        switch route {
        case .agentLoop:
            coordinator.send(
                message: text,
                conversationID: conversationID,
                attachments: staged,
                oneShotWebSearch: searchThisTurn
            )
        case .deepResearch:
            // The same launch the main window uses, on the island's own thread — so the
            // report lands in the conversation `Open in Logue` carries across, rather than
            // somewhere the island cannot show.
            //
            // Staged files are deliberately not passed: the research pipeline reads from the
            // library and the web, and takes no attachments on either surface. Anyone who
            // dropped a file in gets it back on the pill rather than silently losing it.
            attachments = staged
            deepResearch.start(
                prompt: text,
                in: conversationID,
                oneShotWebSearch: searchThisTurn
            )
        case let .imagePlayground(concept):
            // ImagePlayground presents a sheet, which a floating pill cannot host. Answer it
            // as a normal turn rather than silently dropping the send.
            coordinator.send(
                message: concept,
                conversationID: conversationID,
                attachments: staged,
                oneShotWebSearch: searchThisTurn
            )
        }
    }

    /// Tool calls from this thread that are waiting on the user.
    ///
    /// The island runs the full agent loop as of #61, which means it runs the approval gate
    /// too — and the gate blocks the run until someone answers. With no prompt here, a
    /// destructive tool asked for from the island showed nothing, sat for
    /// `approvalTimeoutSeconds` (five minutes), and then failed. The run looked frozen and
    /// there was no way to say yes.
    ///
    /// Only calls that need an answer are rendered. Completed tool calls stay filtered out of
    /// the island — the main window shows those as history, and a pill floating over another
    /// app has no room for a transcript of everything the agent did. What it must show is
    /// what it is blocking on.
    private var pendingApprovals: [AgentToolCall] {
        guard let conversationID,
              let conversation = store.conversations.first(where: { $0.id == conversationID })
        else { return [] }
        return AgentToolTimeline.awaitingApproval(in: conversation.messages)
    }

    /// The error for this thread, if the last run left one.
    ///
    /// Scoped like every other read: an error from a run the main window started is that
    /// window's to report, and showing it here would blame the island for something it did
    /// not do.
    private var currentError: String? {
        guard let conversationID else { return nil }
        return coordinator.lastError(in: conversationID)
    }

    /// Says when a send failed.
    ///
    /// The island had this and lost it when it moved onto the coordinator: the old bare
    /// completion caught its own error and wrote "No AI model loaded" into the bubble, and
    /// that path went away with the `chatStream` call. Without this the most likely failure
    /// a first-time user hits — no model set up yet — makes the send appear to vanish.
    ///
    /// Narrower than the main window's banner because the pill is narrow: the same
    /// dismissable shape, without the second line of detail there is no room for.
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppThemeConstants.error)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            Button {
                withAnimation { coordinator.dismissError() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppThemeConstants.error.opacity(AppThemeConstants.hoverOpacity))
    }

    /// Hands the island's thread to the main window and steps out of the way.
    ///
    /// Only reachable once a thread exists — before the first send there is nothing to carry,
    /// and selecting a conversation that does not exist would leave the main window on an
    /// empty landing state that looks like the send was lost.
    ///
    /// `chatFocusInput` rather than `chatNewConversation`: the latter *creates* a
    /// conversation, which is the opposite of what this does. This one surfaces Home and
    /// focuses the input, leaving the selected thread alone — which is what "continue this
    /// conversation over there" means.
    private func openInLogue() {
        guard let conversationID else { return }
        // Selecting before activating, so the window is already showing the right thread when
        // it comes forward rather than visibly switching to it afterwards.
        store.selectedConversationID = conversationID
        // Activating is not enough. With the main window closed or minimised there is no
        // window to come forward and no `MainWindowView` to observe `.chatFocusInput`, so the
        // button dismissed the island, made Logue frontmost, and showed nothing — leaving the
        // thread it promised to carry over unreachable until the user opened a window by hand.
        AppDelegate.bringMainWindowForward()
        NotificationCenter.default.post(name: .chatFocusInput, object: nil)
        onDismiss()
    }

    /// The island's thread, made on first use.
    ///
    /// Deliberately not selected — see `conversationID`. Titled so it is identifiable in the
    /// main window's list rather than appearing as another "New Conversation" the user did
    /// not knowingly start.
    private func ensureConversation() -> UUID {
        if let conversationID {
            return conversationID
        }
        let conversation = store.createConversation(title: "Command Center", select: false)
        conversationID = conversation.id
        return conversation.id
    }

    // Extension-visible: +Composer
    func stopStreaming() {
        cancelWhicheverIsRunning()
        isInputFocused = true
    }

    /// Stops the pipeline that is actually answering.
    ///
    /// Two coordinators can be behind the Stop button now, and they do not know about each
    /// other. Cancelling only the agent loop while Deep Research was the one running left the
    /// run going with nothing on screen able to stop it — the button reported success and the
    /// report arrived minutes later.
    private func cancelWhicheverIsRunning() {
        if let conversationID, deepResearch.isRunning(in: conversationID) {
            deepResearch.cancel()
        } else {
            coordinator.cancel()
        }
    }

    /// Starts a fresh thread rather than erasing one.
    ///
    /// The old island discarded its messages because they existed nowhere else. They are a
    /// real conversation now, so "clear" means the island stops pointing at it — deleting it
    /// would throw away something the user can still open from the main window.
    private func clearSession() {
        cancelWhicheverIsRunning()
        synthesizer.stopSpeaking(at: .immediate)
        speakingMessageID = nil
        conversationID = nil
        inputText = ""
        isInputFocused = true
    }

    // Extension-visible: +Bubbles
    func speakMessage(_ message: EphemeralChatMessage) {
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

    // Extension-visible: +Bubbles
    func saveMessageAsNote(_ message: EphemeralChatMessage) {
        MessageActions.saveAsNote(message.content)
        savedMessageID = message.id
        Task {
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            if savedMessageID == message.id {
                savedMessageID = nil
            }
        }
    }

    // Extension-visible: +Bubbles
    func copyToClipboard(_ message: EphemeralChatMessage) {
        MessageActions.copyToClipboard(message.content)
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: AppConstants.Delays.toastDismiss)
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }
}
