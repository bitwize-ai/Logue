import SwiftUI
import Textual

/// How one turn is drawn in the island, and what you can do with it.
///
/// Split out because `CommandCenterChatView` went past the 450-line body cap once it grew an
/// error banner. Rendering is the cohesive half: the view itself is now the panel, the prompt
/// pill and the wiring to the coordinator, and this is what a message looks like.
extension CommandCenterChatView {
    /// One row: a turn, or a card for work the agent did between turns.
    ///
    /// The card is the same `ToolExecutionCard` the main window uses rather than an island
    /// variant, per #61's rule that a feature is mounted by both surfaces and not drawn twice.
    /// It has no `conversationID`, which is what keeps it read-only: approval belongs to the
    /// strip pinned above the pill, where an answer cannot scroll out of reach.
    @ViewBuilder
    func islandRow(_ row: IslandRow) -> some View {
        switch row {
        case let .message(message):
            // The assistant turn being written starts empty, and the thinking row speaks for
            // it until it has words. Drawn empty it is a zero-height row the list still
            // spaces around — a gap above the thinking row that closes on the first token.
            if message.isUser || !message.content.isEmpty {
                messageBubble(message)
            }
        case let .tool(entry):
            ToolExecutionCard(toolCall: entry.call, result: entry.result, conversationID: nil)
        }
    }

    /// The panel in `CommandCenterChatView` renders this, so it crosses the file boundary.
    func messageBubble(_ message: EphemeralChatMessage) -> some View {
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
                } else if !message.content.isEmpty {
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

    /// The pulsing row the main window shows in the gap before the first token.
    ///
    /// The island had nothing here. Between a send and the first token it showed the user's
    /// own bubble and empty space — which is the moment someone concludes the send did not
    /// land and presses Return again.
    var thinkingRow: some View {
        HStack(spacing: 8) {
            PulsingDot()
            Text(AgentThinkingState.label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AgentThinkingState.label)
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
    func errorBanner(_ message: String, onDismiss: @escaping () -> Void) -> some View {
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
                withAnimation(IslandMotion.control(reduceMotion: reduceMotion), onDismiss)
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

    private func markdownContent(_ message: EphemeralChatMessage) -> some View {
        // No placeholder. An empty streaming bubble used to render a literal "..." through
        // the markdown renderer; the thinking row says the same thing properly, and saying it
        // twice put a grey box under it with three dots in it.
        StructuredText(markdown: message.content)
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

            Button {
                MessageActions.exportMarkdown(message.content)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption2.weight(.medium))
                    Text("Export")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("Export as Markdown")

            Button { speakMessage(message) } label: {
                HStack(spacing: 3) {
                    Image(systemName: readAloud.isSpeaking(content: message.content) ? "stop.fill" : "speaker.wave.2")
                        .font(.caption2.weight(.medium))
                    Text(readAloud.isSpeaking(content: message.content) ? "Stop" : "Speak")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(readAloud.isSpeaking(content: message.content) ? AppThemeConstants.error : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
    }
}
