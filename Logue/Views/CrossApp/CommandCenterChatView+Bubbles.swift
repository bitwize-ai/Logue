import SwiftUI
import Textual

/// How one turn is drawn in the island, and what you can do with it.
///
/// Split out because `CommandCenterChatView` went past the 450-line body cap once it grew an
/// error banner. Rendering is the cohesive half: the view itself is now the panel, the prompt
/// pill and the wiring to the coordinator, and this is what a message looks like.
extension CommandCenterChatView {
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
}
