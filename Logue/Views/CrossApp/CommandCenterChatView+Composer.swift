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
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Everything that arms or attaches, in one menu — the same one the main
            // window mounts. It used to be three separate glyphs here, which is the
            // per-surface redraw #61 exists to stop, and left no way to reach tool
            // settings from the island at all.
            ComposerPlusMenu(
                surface: .island,
                isDisabled: isGenerating,
                style: .island,
                onAttach: {
                    Task { @MainActor in
                        let picked = await AttachmentIntake.pickFiles()
                        attachments = AttachmentIntake.merging(picked, into: attachments)
                    }
                }
            )

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
                    } else if canSend, !LLMEngineStatus.shared.isBusy {
                        // The same condition the Send button is disabled on. Without it
                        // Return sent while the button beside it refused to, which reads as
                        // the button being broken.
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
            .islandControl(IslandControlCopy.microphone(isRecording: voiceManager.isRecording))

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
                .islandControl(IslandControlCopy.send(canSend: canSend, isGenerating: true))
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSend && !LLMEngineStatus.shared.isBusy ? .white : .white.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                canSend && !LLMEngineStatus.shared.isBusy
                                    ? AppThemeConstants.brandPrimary
                                    : Color.white.opacity(0.08)
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend || LLMEngineStatus.shared.isBusy)
                .keyboardShortcut(.return, modifiers: .command)
                .islandControl(IslandControlCopy.send(canSend: canSend, isGenerating: false))
            }
        }
        .animation(IslandMotion.control(reduceMotion: reduceMotion), value: canSend)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .islandSurface(cornerRadius: 22)
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
    ///
    /// Part of the island's layout rather than an overlay floating above the pill. As an
    /// overlay it took no space, so with a conversation on screen it drew over the bottom of
    /// the transcript — and nothing bounded it, so six files ran the row off both ends.
    var stagedChips: some View {
        let layout = ComposerChipRow.layout(
            modeCount: activeModes.count,
            attachmentCount: attachments.count
        )
        let shown = attachments.prefix(layout.attachments)

        return HStack(spacing: 6) {
            ForEach(activeModes) { mode in
                ModeChip(title: mode.title, systemImage: mode.systemImage, tint: mode.tint) {
                    mode.turnOff()
                }
            }
            ForEach(shown) { attachment in
                attachmentChip(attachment)
            }
            if layout.showsOverflow {
                Text("+\(layout.hidden) more")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .help(hiddenNames(after: layout.attachments))
                    .accessibilityLabel("\(layout.hidden) more attachments: \(hiddenNames(after: layout.attachments))")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    /// The names behind the counter, so nothing is unreachable — hover, or VoiceOver, reads
    /// them out. A chip that hides a file with no way to find out which one is worse than a
    /// row that overflows.
    private func hiddenNames(after shown: Int) -> String {
        attachments.dropFirst(shown).map(\.displayName).joined(separator: ", ")
    }

    private func attachmentChip(_ attachment: TempAttachment) -> some View {
        HStack(spacing: 4) {
            // The attachment's own icon, as the main window shows it. Hardcoding
            // "doc" here made a PDF and a spreadsheet look identical on the island
            // and different in the main window — per-surface drift in a chip that
            // was copied rather than shared.
            Image(systemName: attachment.iconName)
                .font(.caption2)
            Text(attachment.displayName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
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

    /// The per-send modes that are on, in the order they are drawn.
    ///
    /// Modelled so the count is a number `ComposerChipRow` can be handed rather than two
    /// booleans the row has to remember to add up.
    private var activeModes: [ComposerMode] {
        var modes: [ComposerMode] = []
        if isDeepResearchOnce {
            modes.append(
                ComposerMode(
                    id: "deepResearch",
                    title: UICopy.Input.deepResearch,
                    systemImage: "sparkle.magnifyingglass",
                    tint: AppThemeConstants.brandPrimary
                ) { isDeepResearchOnce = false }
            )
        }
        if isWebSearchOnce {
            modes.append(
                ComposerMode(
                    id: "search",
                    title: UICopy.Input.webSearch,
                    systemImage: "globe",
                    tint: AppThemeConstants.brandPrimary
                ) { isWebSearchOnce = false }
            )
        }
        return modes
    }
}

/// One per-send mode, as the chip row draws it.
///
/// A value rather than two booleans read in three places, so the row can count them and the
/// order they appear in is stated once.
struct ComposerMode: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let turnOff: () -> Void
}
