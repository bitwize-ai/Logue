import AppKit
import os.log
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Input Bar

extension AgentChatView {
    /// ChatGPT-style chat input card. Renders as a centered max-width card with
    /// the text field on top, attachment chips above (when present), and a single
    /// bottom toolbar housing paperclip / Web Search / Deep Research / Mic / Send.
    /// The card itself owns its rounded background, border, and shadow — the
    /// parent view (AgentChatView) handles horizontal centering and the
    /// `matchedGeometryEffect` for empty-state ↔ bottom-anchored animation.
    struct InputBarView: View {
        @Binding var inputText: String
        @Binding var attachments: [TempAttachment]
        /// Per-send flags use @AppStorage instead of @Binding<Bool> because
        /// SwiftUI's Menu silently drops Button.action closures on macOS — the
        /// only reliable way to flip these from inside a Menu is to bind a
        /// Toggle to a UserDefault (AppStorage). The AgentCoordinator and the
        /// parent's onSend handler also read these defaults, so all three
        /// surfaces (Menu, chip, send) see the same value.
        @AppStorage(AppConstants.UserDefaultsKeys.oneShotWebSearch)
        var isWebSearchOnce: Bool = false
        @AppStorage(AppConstants.UserDefaultsKeys.oneShotDeepResearch)
        var isDeepResearch: Bool = false
        let isProcessing: Bool
        let isBusy: Bool
        var onSend: () -> Void
        var onCancel: () -> Void

        @State private var inputHeight: CGFloat = 22
        @State private var requestFocus = false
        @State private var isDropTargeted = false
        @State private var dictation = AgentDictationService.shared
        /// Snapshot of `inputText` taken when dictation starts. Used to splice
        /// the live transcript onto the existing typed text instead of overwriting.
        @State private var dictationBaseText: String = ""
        @FocusState private var isFocused: Bool

        /// Drop allowlist. `UTType.fileURL` lets Finder hand us any file; the
        /// loader checks the extension. The Office and image types are listed
        /// explicitly so SwiftUI shows the correct drop indicator on hover.
        static let acceptedDropTypes: [UTType] = [
            .fileURL, .pdf, .plainText, .text, .image,
            UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
            UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
            UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        ]
        /// File-picker allowlist. Same set, but the picker filters more strictly
        /// than the drop target.
        static let acceptedPickerTypes: [UTType] = [
            .pdf, .plainText, .text, .image,
            UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
            UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
            UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        ]

        var body: some View {
            VStack(spacing: 0) {
                if !attachments.isEmpty {
                    attachmentsRow
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                }

                // Active-mode chips appear above the input as a second row
                // when one or more per-send modes are turned on (Search,
                // Deep research). Clicking the × on a chip turns it off.
                // The whole capsule looks like one card; the chip row sits
                // above the input row inside the same rounded background.
                if hasActiveModes {
                    activeModeChips
                        .padding(.horizontal, 14)
                        .padding(.top, attachments.isEmpty ? 8 : 4)
                        .padding(.bottom, 4)
                }

                // Claude.ai-style two-row rectangle. Text field spans the full
                // width on top; toolbar row beneath has the + menu pinned left
                // and dictation + send pinned right. Card grows vertically as
                // the text grows (max 160 pt) so long prompts still fit.
                ChatInputField(
                    text: $inputText,
                    height: $inputHeight,
                    onSubmit: {
                        guard canSend else { return }
                        onSend()
                    },
                    requestFocus: $requestFocus
                )
                .frame(height: min(max(inputHeight, 22), 160))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, attachments.isEmpty && !hasActiveModes ? 12 : 8)

                HStack(alignment: .center, spacing: 8) {
                    plusMenuButton
                    Spacer(minLength: 0)
                    micButton
                    sendButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .padding(.top, 2)
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            .background(cardBackground)
            .overlay(cardBorder)
            .animation(Motion.spring, value: hasActiveModes)
            // Phase A0: char counter near context-limit, sits subtly above the
            // card so it doesn't compete for attention until it matters.
            .overlay(alignment: .topTrailing) {
                CharCounter(count: inputText.count, limit: contextCharLimit)
                    .padding(.top, -10)
                    .padding(.trailing, 8)
            }
            .overlay(alignment: .top) {
                if isDropTargeted {
                    Text("Drop files to attach")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppThemeConstants.brandPrimary)
                        .padding(.top, 6)
                }
            }
            .onDrop(
                of: Self.acceptedDropTypes,
                isTargeted: $isDropTargeted
            ) { providers in
                handleDrop(providers: providers)
                return true
            }
            .onAppear {
                // Focus the input on appear
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.chatInputRefocusInterval) {
                    requestFocus = true
                }
            }
        }

        // MARK: - Active-Mode Chips

        /// True when any per-send mode is on. Drives whether the chip row
        /// renders (turning the pill into a 2-row card).
        private var hasActiveModes: Bool {
            isWebSearchOnce || isDeepResearch
        }

        /// Horizontal row of chips for the modes currently on. Each chip has
        /// an `×` to turn that mode off without opening the + menu.
        private var activeModeChips: some View {
            HStack(spacing: 6) {
                if isWebSearchOnce {
                    modeChip(
                        title: "Search",
                        systemImage: "globe",
                        tint: AppThemeConstants.brandPrimary
                    ) {
                        isWebSearchOnce = false
                    }
                }
                if isDeepResearch {
                    modeChip(
                        title: "Deep research",
                        systemImage: "sparkle.magnifyingglass",
                        tint: AppThemeConstants.brandPrimary
                    ) {
                        isDeepResearch = false
                    }
                }
                Spacer(minLength: 0)
            }
        }

        private func modeChip(
            title: String,
            systemImage: String,
            tint: Color,
            onDismiss: @escaping () -> Void
        ) -> some View {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Turn off \(title)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(
                Capsule().fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.5)
            )
            .transition(.scale.combined(with: .opacity))
        }

        // MARK: - Card Chrome

        /// Claude.ai-style rectangular card. Softer corner radius than the
        /// previous capsule so the text field reads as a rectangle, with the
        /// toolbar row tucked into the bottom of the same card.
        private var cardBackground: some View {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        }

        private var cardBorder: some View {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDropTargeted
                        ? AppThemeConstants.brandPrimary.opacity(0.5)
                        : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        }

        // MARK: - + Menu (ChatGPT-style)

        /// Single + button on the left of the pill. Opens a popup with all the
        /// per-send toggles and quick actions — collapses paperclip, web
        /// search, deep research, image generation, expert activation, and
        /// reasoning visibility into one discoverable surface.
        private var plusMenuButton: some View {
            Menu {
                Button {
                    openFilePicker()
                } label: {
                    Label("Add photos & files", systemImage: "paperclip")
                }
                .keyboardShortcut("u", modifiers: .command)

                // Set explicit values (not `.toggle()`) — on macOS the
                // Menu's deferred close pipeline can swallow a Bool.toggle()
                // call against an `@Binding`. Hand-write the new value AND
                // mirror it to a UserDefault that the AgentCoordinator reads
                // at send time, so the agent sees the toggle even if a
                // late-propagating Menu binding loses the race.
                // Toggles inside a Menu render as native NSMenuItems with a
                // checkmark when on. Binding straight to @AppStorage (instead
                // of an @Binding<Bool>) sidesteps the Menu close pipeline
                // race that drops Button.action closures on macOS.
                Toggle(isOn: $isWebSearchOnce) {
                    Label("Search the web", systemImage: "globe")
                }
                Toggle(isOn: $isDeepResearch) {
                    Label("Deep research", systemImage: "sparkle.magnifyingglass")
                }

                Divider()

                Button {
                    SettingsNavigator.shared.pendingTab = .ai
                    NotificationCenter.default.post(name: .openSettingsGeneral, object: nil)
                } label: {
                    Label("Tool settings…", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Attach, search, deep research…")
            .disabled(isProcessing || isBusy)
        }

        private var micButton: some View {
            Button {
                toggleDictation()
            } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .font(.callout)
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.secondary)
                    .symbolEffect(.pulse, isActive: dictation.isRecording)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(dictation.isRecording ? "Stop dictation" : "Dictate")
            .disabled(isProcessing || isBusy)
        }

        @ViewBuilder
        private var sendButton: some View {
            if isProcessing {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop processing")
            } else {
                Button {
                    guard canSend else { return }
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canSend ? AppThemeConstants.brandPrimary : Color.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(isDeepResearch ? "Send · Deep Research" : "Send message")
            }
        }

        // MARK: - Attachments Row

        private var attachmentsRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(attachments) { attachment in
                        attachmentChip(attachment)
                    }
                }
            }
        }

        private func attachmentChip(_ attachment: TempAttachment) -> some View {
            HStack(spacing: 4) {
                Image(systemName: attachment.iconName)
                    .font(.caption)
                Text(attachment.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    attachments.removeAll { $0.id == attachment.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }

        // MARK: - File picker

        /// Opens an `NSOpenPanel` for file selection. Selected URLs go through the
        /// same `TempAttachmentLoader` as drag-and-drop so the resulting chips and
        /// extracted text use one code path. De-duplicates by display name.
        private func openFilePicker() {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = Self.acceptedPickerTypes
            panel.prompt = "Attach"
            panel.message = "Select files to attach to your message"
            panel.begin { response in
                guard response == .OK else { return }
                let urls = panel.urls
                Task { @MainActor in
                    for url in urls {
                        guard let attachment = await TempAttachmentLoader.load(from: url) else { continue }
                        if !attachments.contains(where: { $0.displayName == attachment.displayName }) {
                            attachments.append(attachment)
                        }
                    }
                }
            }
        }

        // MARK: - Drop handling

        private func handleDrop(providers: [NSItemProvider]) {
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL? = switch item {
                    case let dataURL as URL:
                        dataURL
                    case let data as Data:
                        URL(dataRepresentation: data, relativeTo: nil)
                    default:
                        nil
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        if let attachment = await TempAttachmentLoader.load(from: url) {
                            // De-dupe by URL filename — dragging the same file twice is a no-op.
                            if !attachments.contains(where: { $0.displayName == attachment.displayName }) {
                                attachments.append(attachment)
                            }
                        }
                    }
                }
            }
        }

        private var canSend: Bool {
            let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasAttachments = !attachments.isEmpty
            return (hasText || hasAttachments) && !isProcessing && !isBusy
        }

        /// Approximate per-input character budget. Reuses the same accounting
        /// `LLMEngine.maxInputChars(reservedTokens:)` already enforces, so the
        /// counter and the actual truncation gate stay in lockstep.
        private var contextCharLimit: Int {
            LLMEngine.maxInputChars(reservedTokens: AppConstants.LLMDefaults.chatReservedTokens)
        }

        // MARK: - Dictation

        private func toggleDictation() {
            if dictation.isRecording {
                dictation.stop()
                return
            }
            dictationBaseText = inputText
            // The callback updates inputText with the live transcript spliced
            // onto whatever the user already typed.
            dictation.onTranscript = { transcript, _ in
                let separator = dictationBaseText.isEmpty ? "" : " "
                inputText = dictationBaseText + separator + transcript
            }
            Task {
                let started = await dictation.start()
                if !started, let err = dictation.lastError {
                    NSLog("Dictation could not start: \(err)")
                }
            }
        }
    }
}

// MARK: - TempAttachmentLoader

/// Extracts text from a dropped file URL. PDF via PDFKit, plain text via Data
/// + UTF-8, others (e.g. images) get a metadata-only attachment with no
/// extracted text — the agent sees the filename but no content.
///
/// Disk I/O (reading PDF pages, decoding text files) runs on a detached
/// background task so the UI never blocks during a drop or file-picker pick.
enum TempAttachmentLoader {
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "csv", "json", "yaml", "yml",
        "swift", "py", "js", "ts", "html", "css",
    ]
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "tif",
    ]
    /// Microsoft Office Open XML formats. Extracted via `OfficeExtractor`
    /// which uses an inline ZIP+DEFLATE parser (no subprocess, no third-party
    /// dependency) to walk the archive and pull out the text-bearing XML parts.
    private static let officeExtensions: Set<String> = ["xlsx", "docx", "pptx"]

    /// Async loader. Disk reads run off the main thread.
    static func load(from url: URL) async -> TempAttachment? {
        let displayName = url.lastPathComponent
        let lowerExt = url.pathExtension.lowercased()

        if lowerExt == "pdf" {
            return await loadPDF(url: url, displayName: displayName)
        }
        if textExtensions.contains(lowerExt) {
            return await loadText(url: url, displayName: displayName)
        }
        if officeExtensions.contains(lowerExt) {
            return await loadOffice(url: url, displayName: displayName, ext: lowerExt)
        }
        if imageExtensions.contains(lowerExt) {
            return await loadImage(url: url, displayName: displayName)
        }

        // Fallback — unknown type, just record the filename so the user sees feedback.
        return TempAttachment(
            kind: .other,
            displayName: displayName,
            extractedText: "",
            iconName: "paperclip"
        )
    }

    /// PDF extraction — detached so a 100-page PDF doesn't pin the main thread.
    private static func loadPDF(url: URL, displayName: String) async -> TempAttachment {
        await Task.detached(priority: .userInitiated) {
            guard let pdf = PDFDocument(url: url) else {
                return TempAttachment(
                    kind: .pdf,
                    displayName: displayName,
                    extractedText: "",
                    iconName: "doc.fill"
                )
            }
            var combined = ""
            for index in 0 ..< pdf.pageCount {
                if let page = pdf.page(at: index), let text = page.string {
                    combined += text + "\n"
                    if combined.count >= TempAttachment.maxExtractedChars {
                        break
                    }
                }
            }
            let trimmed = String(combined.prefix(TempAttachment.maxExtractedChars))
            return TempAttachment(
                kind: .pdf,
                displayName: displayName,
                extractedText: trimmed,
                iconName: "doc.text.fill"
            )
        }.value
    }

    /// Plain-text extraction — also off-main; even a small file involves a syscall.
    private static func loadText(url: URL, displayName: String) async -> TempAttachment {
        await Task.detached(priority: .userInitiated) {
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                let trimmed = String(raw.prefix(TempAttachment.maxExtractedChars))
                return TempAttachment(
                    kind: .plainText,
                    displayName: displayName,
                    extractedText: trimmed,
                    iconName: "doc.plaintext.fill"
                )
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "TempAttachmentLoader")
                    .warning("Failed to read text attachment: \(error.localizedDescription, privacy: .public)")
                return TempAttachment(
                    kind: .plainText,
                    displayName: displayName,
                    extractedText: "",
                    iconName: "doc.plaintext.fill"
                )
            }
        }.value
    }

    /// Image OCR via the Vision framework. Runs `VNRecognizeTextRequest` so
    /// the agent gets actual readable text instead of just the filename.
    /// Detached for the same reason as PDF/Office — Vision can take a beat.
    private static func loadImage(url: URL, displayName: String) async -> TempAttachment {
        await Task.detached(priority: .userInitiated) {
            let extracted = await ocrTextFromImage(at: url) ?? ""
            return TempAttachment(
                kind: .image,
                displayName: displayName,
                extractedText: String(extracted.prefix(TempAttachment.maxExtractedChars)),
                iconName: "photo.fill"
            )
        }.value
    }

    /// Run Vision OCR on a local image file. Returns nil on any failure
    /// (file unreadable, no text recognized, request errored). Uses
    /// `.accurate` recognition level — the agent benefits from the higher
    /// fidelity even though it's a touch slower.
    private static func ocrTextFromImage(at url: URL) async -> String? {
        guard let nsImage = NSImage(contentsOf: url),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage
        else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    Logger(subsystem: AppConstants.bundleID, category: "ImageOCR")
                        .error("Vision OCR failed: \(error.localizedDescription, privacy: .public)")
                    cont.resume(returning: nil)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "ImageOCR")
                    .error("Vision handler failed: \(error.localizedDescription, privacy: .public)")
                cont.resume(returning: nil)
            }
        }
    }

    /// Office Open XML extraction (.xlsx / .docx / .pptx). Off-main because
    /// the ZIP walk + XML parse + DEFLATE inflate can take real time on a
    /// dense workbook.
    private static func loadOffice(url: URL, displayName: String, ext: String) async -> TempAttachment {
        let kindIcon: (TempAttachment.Kind, String) = switch ext {
        case "xlsx": (.plainText, "tablecells")
        case "docx": (.plainText, "doc.text")
        case "pptx": (.plainText, "rectangle.on.rectangle")
        default: (.plainText, "doc")
        }
        return await Task.detached(priority: .userInitiated) {
            let extracted = OfficeExtractor.extractText(
                from: url,
                maxChars: TempAttachment.maxExtractedChars
            ) ?? ""
            return TempAttachment(
                kind: kindIcon.0,
                displayName: displayName,
                extractedText: extracted,
                iconName: kindIcon.1
            )
        }.value
    }
}
