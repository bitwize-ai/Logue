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

            // Web search for this turn
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isWebSearchOnce.toggle() }
            } label: {
                Image(systemName: "globe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        isWebSearchOnce ? AppThemeConstants.brandPrimary : .white.opacity(0.4)
                    )
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .help(isWebSearchOnce ? "Web search is on for this message" : "Search the web for this message")

            // Deep Research for this turn
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isDeepResearchOnce.toggle() }
            } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        isDeepResearchOnce ? AppThemeConstants.brandPrimary : .white.opacity(0.4)
                    )
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .help(
                isDeepResearchOnce
                    ? "Deep Research is on for this message"
                    : "Research this in depth before answering"
            )
            .accessibilityLabel("Deep Research")
            .accessibilityValue(isDeepResearchOnce ? "On" : "Off")

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

            // What Return will do, once it will do anything.
            //
            // Shown only when there is something to send: a hint that is always there is
            // chrome, and the island has one line to spend. Shift-Return for a newline is
            // deliberately not advertised — it is the escape hatch from the hint, not a
            // second thing to learn.
            if canSend, !isGenerating {
                Text("↩")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }

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
        .animation(.easeOut(duration: 0.12), value: canSend)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .islandSurface(cornerRadius: 22)
        .overlay(alignment: .top) {
            if !attachments.isEmpty || isWebSearchOnce || isDeepResearchOnce {
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

    /// Something to ask, on an island with nothing in it yet.
    ///
    /// The same chips Home offers, from the same rule and the same reading of the workspace —
    /// so the island suggests summarising the meeting you have not summarised rather than a
    /// hardcoded list that goes stale. Hidden until the stores report, because offering
    /// first-run chips to a returning user is worse than offering nothing.
    var starters: some View {
        VStack(spacing: 0) {
            if HomeSuggestions.storesAreLoaded, !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            inputText = chip.prompt
                            isInputFocused = true
                        } label: {
                            Text(chip.label)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(chip.prompt)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private var chips: [HomeSuggestions.Chip] {
        HomeSuggestions.chips(
            for: HomeSuggestions.currentInputs(overdueCount: insights.actionItemStats.overdue)
        )
    }

    /// What is staged for the next send, with a way to take each one back off.
    private var attachmentChips: some View {
        HStack(spacing: 6) {
            if isDeepResearchOnce {
                ModeChip(
                    title: "Deep Research",
                    systemImage: "sparkle.magnifyingglass",
                    tint: AppThemeConstants.brandPrimary
                ) {
                    isDeepResearchOnce = false
                }
            }
            if isWebSearchOnce {
                ModeChip(
                    title: "Search",
                    systemImage: "globe",
                    tint: AppThemeConstants.brandPrimary
                ) {
                    isWebSearchOnce = false
                }
            }
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
