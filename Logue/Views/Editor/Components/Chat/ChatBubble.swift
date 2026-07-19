import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?

    @State private var insertedFeedback = false
    @State private var copiedFeedback = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Group {
                if message.role == .assistant {
                    MarkdownTextView(text: message.content)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if let quoted = message.quotedContext, !quoted.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 2.5)

                                Text(quoted)
                                    .font(.caption)
                                    .opacity(0.8)
                                    .lineLimit(4)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(message.content)
                            .font(.callout)
                    }
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

            // Action row for assistant messages
            if message.role == .assistant {
                HStack(spacing: 8) {
                    if let insertAction = onInsert {
                        Button {
                            insertAction()
                            withAnimation(.easeInOut(duration: 0.2)) { insertedFeedback = true }
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.clipboardFeedback)
                                withAnimation { insertedFeedback = false }
                            }
                        } label: {
                            Label(
                                insertedFeedback ? "Inserted!" : "Insert",
                                systemImage: insertedFeedback ? "checkmark" : "arrow.down.doc"
                            )
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                insertedFeedback ? AppThemeConstants.success.opacity(0.12) : AppThemeConstants.quaternaryFill,
                                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                            )
                            .foregroundStyle(insertedFeedback ? AppThemeConstants.success : .primary)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: insertedFeedback)
                        .accessibilityLabel(insertedFeedback ? "Inserted into document" : "Insert into document")
                        .accessibilityHint("Inserts this response into your document")
                    }

                    if let copyAction = onCopy {
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
                                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                                )
                                .foregroundStyle(copiedFeedback ? AppThemeConstants.success : .secondary)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: copiedFeedback)
                        .help(copiedFeedback ? "Copied!" : "Copy to clipboard")
                        .accessibilityLabel(copiedFeedback ? "Copied to clipboard" : "Copy response to clipboard")
                    }
                }
                .opacity(isHovered || onInsert != nil ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
