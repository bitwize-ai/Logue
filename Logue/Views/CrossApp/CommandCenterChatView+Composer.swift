import SwiftUI

/// The island's composer: the prompt pill, what is staged for the next send, and the two ways
/// a file gets in.
///
/// Split out for the same reason as `+Bubbles` — giving the island attachments took the view's
/// body past the 450-line cap. The intake itself lives in `AttachmentIntake`, shared with the
/// main window; this is only how the island presents it.
extension CommandCenterChatView {
    /// Rendered by the view itself, so it crosses the file boundary.
    var promptPill: some View {
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

            // Attach
            Button {
                Task { @MainActor in
                    let picked = await AttachmentIntake.pickFiles()
                    attachments = AttachmentIntake.merging(picked, into: attachments)
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .help("Attach files")

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
        .overlay(alignment: .top) {
            if !attachments.isEmpty {
                attachmentChips
                    .offset(y: -34)
            }
        }
        // Dropping onto the pill is the same intake as the picker, so a file arrives the
        // same way whichever route the user takes.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                let urls = await AttachmentIntake.urls(from: providers)
                let loaded = await AttachmentIntake.load(urls: urls)
                attachments = AttachmentIntake.merging(loaded, into: attachments)
            }
            return true
        }
    }

    /// What is staged for the next send, with a way to take each one back off.
    private var attachmentChips: some View {
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.caption2)
                    Text(attachment.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(attachment.displayName)")
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }
}
