import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Message List

extension AgentChatView {
    /// Renders the scrollable message list with auto-scroll behavior.
    /// - User sends a message → scrolls it to the **top** of the viewport immediately
    /// - Streaming tokens arrive → keeps bottom visible
    /// - Tool cards appear → scrolls to bottom
    struct MessageListView: View {
        let messages: [AgentMessage]
        let activeToolCalls: [AgentToolCall]
        let isProcessing: Bool
        let isStreaming: Bool
        let streamingText: String
        /// Active conversation ID — needed so approval buttons in tool cards can resolve
        /// the right `ApprovalGate` entry.
        let conversationID: UUID

        /// Monotonic trigger from AgentChatView — increments when user sends a message.
        let scrollToTopTrigger: Int
        /// The user message ID to scroll to the top.
        let scrollTargetID: UUID?
        /// Invoked when the user edits a past question and re-sends it.
        let onRegenerateFromUserMessage: (UUID, String) -> Void

        /// Currently-editing user message ID (only one at a time). Nil = not editing.
        @State private var editingMessageID: UUID?
        @State private var editingText: String = ""

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            messageView(for: message)
                                .id(message.id)
                        }

                        // Show active tool execution
                        ForEach(activeToolCalls) { call in
                            ToolExecutionCard(toolCall: call, result: nil, conversationID: conversationID)
                                .padding(.horizontal, 16)
                                .id("active-\(call.id.uuidString)")
                        }

                        // Processing indicator (only when not streaming and no tool calls active)
                        if isProcessing, activeToolCalls.isEmpty, !isStreaming {
                            HStack(spacing: 8) {
                                PulsingDot()
                                Text("Thinking…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .id("typing-indicator")
                        }

                        // Bottom anchor for scroll-to-bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                    }
                    .padding(.vertical, 16)
                }
                // Direct scroll trigger from user send action — fires before async processing starts
                .onChange(of: scrollToTopTrigger) { _, _ in
                    guard let targetID = scrollTargetID else { return }
                    // Brief yield so LazyVStack renders the new message before we scroll to it
                    DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.chatInputRefocusInterval) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(targetID, anchor: .top)
                        }
                    }
                }
                .onChange(of: activeToolCalls.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: streamingText) { _, _ in
                    // During streaming, keep scrolled to the bottom so new tokens are visible
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
        }

        // MARK: - Message Rendering

        @ViewBuilder
        private func messageView(for message: AgentMessage) -> some View {
            switch message.role {
            case .user:
                userRow(message)
            case .assistant:
                assistantRow(message)
            case .toolCall:
                toolCallView(message)
            case .toolResult:
                toolResultView(message)
            }
        }

        // MARK: - User Message

        @ViewBuilder
        private func userRow(_ message: AgentMessage) -> some View {
            if editingMessageID == message.id {
                userEditRow(messageID: message.id)
            } else {
                userDisplayRow(message)
            }
        }

        /// Static (non-editing) display row: bubble + copy + pencil buttons.
        private func userDisplayRow(_ message: AgentMessage) -> some View {
            VStack(alignment: .trailing, spacing: 4) {
                if !message.attachments.isEmpty {
                    HStack {
                        Spacer(minLength: 60)
                        userAttachmentChips(message.attachments)
                    }
                }
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content.isEmpty ? attachmentPlaceholder(message.attachments) : message.content)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            AppThemeConstants.brandPrimary,
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                        )
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }

                // Copy + Edit actions
                HStack(spacing: 4) {
                    Button {
                        copyToClipboard(message.content)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")

                    Button {
                        editingText = message.content
                        editingMessageID = message.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit message and regenerate")
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal, 16)
        }

        /// Renders a horizontal row of file chips above the user bubble — mirrors
        /// the input bar's chip UI so the user sees what they sent.
        private func userAttachmentChips(_ attachments: [TempAttachment]) -> some View {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: attachment.iconName)
                            .font(.caption2)
                        Text(attachment.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
                }
            }
        }

        /// Stand-in text for the bubble when the user sends attachments without typing.
        private func attachmentPlaceholder(_ attachments: [TempAttachment]) -> String {
            switch attachments.count {
            case 0: ""
            case 1: "Attached: \(attachments[0].displayName)"
            default: "Attached \(attachments.count) files"
            }
        }

        /// Editable row: text editor + cancel/send. Shown when `editingMessageID == message.id`.
        private func userEditRow(messageID: UUID) -> some View {
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer(minLength: 40)
                    TextField("Edit message…", text: $editingText, axis: .vertical)
                        .font(.callout)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)
                        .background(
                            AppThemeConstants.brandPrimary,
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                        )
                        .foregroundStyle(.white)
                        .tint(.white)
                        .onSubmit {
                            commitEdit(messageID: messageID)
                        }
                }

                HStack(spacing: 8) {
                    Button("Cancel") {
                        editingMessageID = nil
                        editingText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        commitEdit(messageID: messageID)
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(AppThemeConstants.brandPrimary)
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
        }

        private func commitEdit(messageID: UUID) {
            let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            editingMessageID = nil
            editingText = ""
            onRegenerateFromUserMessage(messageID, trimmed)
        }

        // MARK: - Assistant Message

        @ViewBuilder
        private func assistantRow(_ message: AgentMessage) -> some View {
            let isLastAssistant = message.id == messages.last(where: { $0.role == .assistant })?.id
            let isLiveStream = isLastAssistant && isStreaming
            let isAwaitingFirstToken = isLiveStream && message.content.isEmpty

            VStack(alignment: .leading, spacing: 6) {
                if isAwaitingFirstToken {
                    // No tokens yet — show a richer pulse instead of a bare spinner.
                    HStack(spacing: 8) {
                        PulsingDot()
                        Text("Thinking…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if !message.content.isEmpty {
                    MarkdownTextView(text: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    // Phase G: render any LaTeX expressions inline below
                    // the markdown text. KaTeX is bundled in Resources;
                    // no network call needed.
                    InlineLaTeXView(messageContent: message.content)

                    if isLiveStream {
                        // Tokens are arriving — show a subtle "Generating…" badge under the message.
                        HStack(spacing: 6) {
                            PulsingDot(size: 6)
                            Text("Generating…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 14)
                        .transition(.opacity)
                    } else {
                        // Settled message — show copy/export actions.
                        assistantActionRow(content: message.content)
                    }
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: isLiveStream)
        }

        private func assistantActionRow(content: String) -> some View {
            // Wrap in a value type so this row can own its own `@State` for the
            // chart sheet (a function returning `some View` cannot host state).
            AssistantActionRow(content: content)
        }

        // MARK: - Tool Messages

        private func toolCallView(_ message: AgentMessage) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(message.toolCalls) { call in
                    // Find matching result in subsequent messages
                    let result = findResult(for: call.id, in: messages)
                    // If the stored status is .needsConfirmation but a result has arrived, the
                    // approval was resolved elsewhere — treat it as completed/failed.
                    let displayStatus: AgentToolCallStatus = {
                        if let result {
                            return result.isError ? .failed : .completed
                        }
                        return call.status
                    }()
                    ToolExecutionCard(
                        toolCall: AgentToolCall(
                            id: call.id,
                            toolName: call.toolName,
                            arguments: call.arguments,
                            status: displayStatus,
                            clearance: call.clearance
                        ),
                        result: result,
                        conversationID: conversationID
                    )
                }
            }
            .padding(.horizontal, 16)
        }

        private func toolResultView(_ message: AgentMessage) -> some View {
            // Tool results are displayed inline in the ToolExecutionCard above
            // so we render them as invisible to avoid duplication
            EmptyView()
        }

        /// Finds the tool result matching a tool call ID from subsequent messages.
        private func findResult(for toolCallID: UUID, in messages: [AgentMessage]) -> AgentToolResult? {
            for message in messages where message.role == .toolResult {
                if let result = message.toolResult, result.toolCallID == toolCallID {
                    return result
                }
            }
            return nil
        }

        // MARK: - Clipboard / Export

        private func copyToClipboard(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            HapticFeedback.copy()
            Task { @MainActor in
                ToastCenter.shared.show(UICopy.Toast.copied)
            }
        }

        private func exportMarkdown(_ text: String) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType("net.daringfireball.markdown") ?? .plainText]
            panel.nameFieldStringValue = "logue-response.md"
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSLog("Failed to export markdown: \(error.localizedDescription)")
                }
            }
        }
    }
}
