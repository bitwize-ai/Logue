import AppKit
import os.log
import SwiftUI

// MARK: - InlineAssistantController

/// Phase D: system-wide inline writing assistant. Bound to ⌘⌃I.
///
/// Flow:
///   1. User selects text in any app, presses ⌘⌃I.
///   2. Controller reads the selection via `AccessibilityService` (with
///      a clipboard-pivot fallback for apps that don't expose AX text).
///   3. Floating panel appears at the cursor position with action buttons.
///   4. User picks an action (Simplify / Expand / Fix Grammar / etc.).
///   5. Controller invokes `LLMEngine.complete()` with a tailored prompt.
///   6. Result is written back via `replaceSelectedText`.
@MainActor
@Observable
final class InlineAssistantController {
    static let shared = InlineAssistantController()

    private(set) var isVisible: Bool = false
    private(set) var selectedText: String = ""
    private(set) var isProcessing: Bool = false
    /// Phase G: word-stepping suggestion buffer. Populated by
    /// `Answer Question`; consumed by Tab (insert next word) and
    /// Shift+Tab (insert all remaining). Empty when no suggestion is
    /// active.
    private(set) var pendingSuggestion: String = ""
    private(set) var pendingSuggestionConsumedPrefix: String = ""

    private var panel: InlineAssistantPanel?
    private var sourceAppPID: pid_t?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "InlineAssistant")

    /// Per-app exclusion list — apps where the assistant won't appear.
    /// Persisted as a comma-separated bundle ID list.
    private static let exclusionsKey = "inlineAssistant.excludedBundleIDs"

    static func excludedBundleIDs() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: exclusionsKey) ?? ""
        return Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private init() {}

    /// Entry point — bound to the ⌘⌃I global shortcut by AppDelegate.
    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }

        // Permission check up front — without Accessibility we can't read selection
        // from other apps. Prompt on first use; if denied, surface a recoverable toast.
        if !AccessibilityService.shared.checkAccessibilityPermission(prompt: true) {
            ToastCenter.shared.show(
                "Grant Accessibility to use ⌘⌃I — System Settings → Privacy",
                kind: .warning
            )
            logger.info("Inline assistant blocked: Accessibility not granted")
            return
        }

        // Honor exclusion list before doing anything privacy-relevant.
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontApp.bundleIdentifier,
           Self.excludedBundleIDs().contains(bundleID)
        {
            logger.info("Inline assistant suppressed for excluded app: \(bundleID, privacy: .public)")
            return
        }

        sourceAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Pull selection (AX-first, clipboard fallback).
        let text = AccessibilityService.shared.getSelectedText() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastCenter.shared.show("Select some text first", kind: .info)
            return
        }
        selectedText = text

        let cursor = AccessibilityService.shared.getCursorScreenPosition() ?? .zero
        presentPanel(at: cursor)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        // Return focus to the source app so the user keeps their context.
        if let pid = sourceAppPID,
           let app = NSRunningApplication(processIdentifier: pid)
        {
            app.activate()
        }
    }

    // MARK: - Action execution

    /// Prompt commands the user can pick from the floating panel.
    enum Action: String, CaseIterable, Identifiable {
        case answerQuestion = "Answer Question"
        case simplify = "Simplify"
        case expand = "Expand"
        case fixGrammar = "Fix Grammar"
        case makeFormal = "Make Formal"
        case makeCasual = "Make Casual"
        case translate = "Translate"
        case summarize = "Summarize"

        var id: String {
            rawValue
        }

        /// Phase G: when true, the panel keeps its result visible so the
        /// user can step through it word-by-word with Tab / Shift+Tab
        /// instead of replacing the source selection. "Answer Question"
        /// is the canonical use case — the selection is a question and
        /// the generated answer is what the user wants to insert.
        var supportsWordStepping: Bool {
            switch self {
            case .answerQuestion: true
            default: false
            }
        }

        var icon: String {
            switch self {
            case .answerQuestion: "text.cursor"
            case .simplify: "arrow.down.right.and.arrow.up.left"
            case .expand: "arrow.up.left.and.arrow.down.right"
            case .fixGrammar: "checkmark.seal"
            case .makeFormal: "graduationcap"
            case .makeCasual: "bubble.left.and.bubble.right"
            case .translate: "globe"
            case .summarize: "text.alignleft"
            }
        }

        func systemPrompt() -> String {
            let base = "You are a writing assistant. Output only the rewritten text — no preamble, no explanation, no markdown fences."
            switch self {
            case .answerQuestion:
                return "You are a writing assistant. The user has selected a question or prompt and wants you to "
                    + "draft a concise answer they can insert back into their document. Output ONLY the answer "
                    + "as plain prose — no preamble, no explanation, no markdown fences. 1-3 sentences unless "
                    + "the question explicitly asks for more."
            case .simplify:
                return "\(base) Rewrite the user's text in simpler, plainer English while preserving meaning."
            case .expand:
                return "\(base) Expand the user's text with more detail and clarification, keeping the tone."
            case .fixGrammar:
                return "\(base) Fix grammar, spelling, and punctuation. Do not change wording style or meaning."
            case .makeFormal:
                return "\(base) Rewrite the user's text in a more formal, professional register."
            case .makeCasual:
                return "\(base) Rewrite the user's text in a casual, friendly register."
            case .translate:
                let translateNote = "If it's already English, translate to the user's likely native language based on context."
                return "\(base) Translate the user's text to English. \(translateNote)"
            case .summarize:
                return "\(base) Summarize the user's text in 1-2 sentences."
            }
        }
    }

    /// Run an action on the captured selection. Replaces the selected text
    /// in-place when complete. Posts a toast + haptic on done/error.
    /// For `Answer Question` (and any future word-stepping action), the
    /// generated text is held in `pendingSuggestion` instead of being
    /// auto-inserted — Tab / Shift+Tab consume it from the panel.
    func run(action: Action, customPrompt: String? = nil) {
        guard !isProcessing else { return }
        isProcessing = true
        let textToRewrite = selectedText

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let system = customPrompt ?? action.systemPrompt()
                // XML-wrap user content per CLAUDE.md.
                let user = "<text>\n\(textToRewrite)\n</text>"
                let rewrite = try await LLMEngine.shared.complete(system: system, prompt: user)
                let cleaned = rewrite
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```", with: "")

                if action.supportsWordStepping {
                    pendingSuggestion = cleaned
                    pendingSuggestionConsumedPrefix = ""
                    isProcessing = false
                    HapticFeedback.send()
                    return
                }
                replaceInSourceApp(with: cleaned)
                dismiss()
                ToastCenter.shared.show(UICopy.Toast.saved)
            } catch {
                logger.error("Inline assistant failed: \(error.localizedDescription, privacy: .public)")
                ToastCenter.shared.show("Couldn't rewrite", kind: .warning)
            }
            isProcessing = false
        }
    }

    // MARK: - Tab / Shift+Tab word stepping (Phase G)

    /// Insert the next whitespace-delimited token from `pendingSuggestion`
    /// into the source app at the current caret position. Removes the
    /// inserted prefix from the buffer; auto-dismisses when empty.
    func insertNextWord() {
        let remainder = remainingSuggestion()
        guard !remainder.isEmpty else { return }
        // Find the next word boundary — include a single trailing space
        // when present so successive Tab presses place natural spacing.
        let nextChunk = remainder.firstWordWithTrailingSpace()
        guard !nextChunk.isEmpty else { return }
        appendToSourceApp(nextChunk)
        pendingSuggestionConsumedPrefix += nextChunk
        if remainingSuggestion().isEmpty {
            discardSuggestion()
            ToastCenter.shared.show(UICopy.Toast.saved)
        }
    }

    /// Insert the entire remainder at once, then dismiss.
    func insertAllRemaining() {
        let remainder = remainingSuggestion()
        guard !remainder.isEmpty else { return }
        appendToSourceApp(remainder)
        pendingSuggestionConsumedPrefix = pendingSuggestion
        discardSuggestion()
        ToastCenter.shared.show(UICopy.Toast.saved)
    }

    /// Throw away the current suggestion without inserting anything else.
    /// Returns the panel to its action-grid state.
    func discardSuggestion() {
        pendingSuggestion = ""
        pendingSuggestionConsumedPrefix = ""
    }

    /// What's left of the suggestion to insert.
    private func remainingSuggestion() -> String {
        guard pendingSuggestion.hasPrefix(pendingSuggestionConsumedPrefix) else {
            return pendingSuggestion
        }
        return String(pendingSuggestion.dropFirst(pendingSuggestionConsumedPrefix.count))
    }

    /// Switch focus to the source app and type the chunk at the caret.
    /// Uses the same AX-driven path as `replaceInSourceApp`.
    private func appendToSourceApp(_ chunk: String) {
        if let pid = sourceAppPID,
           let app = NSRunningApplication(processIdentifier: pid)
        {
            app.activate()
        }
        AccessibilityService.shared.insertTextAtCursor(chunk)
    }

    private func replaceInSourceApp(with text: String) {
        // Switch focus back to source briefly so the AX replace targets it.
        if let pid = sourceAppPID,
           let app = NSRunningApplication(processIdentifier: pid)
        {
            app.activate()
        }
        _ = AccessibilityService.shared.replaceSelectedText(with: text)
    }

    // MARK: - Panel presentation

    private func presentPanel(at point: CGPoint) {
        let view = InlineAssistantPanelView(controller: self)
        let panel = InlineAssistantPanel(rootView: view)
        let size = NSSize(width: 280, height: 280)
        let origin = NSPoint(
            x: max(20, min(point.x - size.width / 2, (NSScreen.main?.frame.maxX ?? 1440) - size.width - 20)),
            y: max(20, point.y - size.height - 12)
        )
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        isVisible = true
    }
}

// MARK: - Word-stepping helpers (Phase G)

private extension String {
    /// Returns the next word from the front of the string, including a
    /// single trailing whitespace if present so successive insertions
    /// produce natural spacing. Returns the whole string when no
    /// whitespace boundary is found.
    func firstWordWithTrailingSpace() -> String {
        guard !isEmpty else { return "" }
        if let firstSpaceRange = rangeOfCharacter(from: .whitespacesAndNewlines) {
            // Include up to and including the whitespace character.
            let endIdx = index(after: firstSpaceRange.lowerBound)
            return String(self[startIndex ..< endIdx])
        }
        return self
    }
}

// MARK: - Panel window

/// Frameless floating panel for the inline assistant.
final class InlineAssistantPanel: NSPanel {
    init(rootView: InlineAssistantPanelView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool {
        true
    }
}

// MARK: - SwiftUI view

struct InlineAssistantPanelView: View {
    @State var controller: InlineAssistantController
    @State private var customDraft: String = ""
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if controller.isProcessing {
                processingState
            } else if !controller.pendingSuggestion.isEmpty {
                // Phase G: Tab / Shift+Tab consume the suggestion buffer
                // word-by-word or all-at-once.
                suggestionStepperView
            } else {
                actionGrid
                customField
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .onExitCommand { controller.dismiss() }
    }

    // MARK: - Suggestion stepper (Phase G)

    /// Pane shown when an `Answer Question` suggestion is ready. The
    /// remaining text is highlighted; Tab inserts the next word at the
    /// caret in the source app, Shift+Tab inserts the whole remainder.
    private var suggestionStepperView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("Suggestion")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("Tab · word    ⇧Tab · all")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(controller.pendingSuggestion)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )

            HStack(spacing: 6) {
                Button {
                    controller.insertNextWord()
                } label: {
                    Label("Insert next word", systemImage: "arrow.right.to.line")
                        .font(.caption)
                }
                .keyboardShortcut(.tab, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    controller.insertAllRemaining()
                } label: {
                    Label("Insert all", systemImage: "arrow.right.doc.on.clipboard")
                        .font(.caption)
                }
                .keyboardShortcut(.tab, modifiers: .shift)
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                Button("Discard") {
                    controller.discardSuggestion()
                }
                .controlSize(.small)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text("Logue")
                .font(.callout.weight(.semibold))
            Spacer()
            Button {
                controller.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var actionGrid: some View {
        let actions = InlineAssistantController.Action.allCases
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(actions) { action in
                Button {
                    controller.run(action: action)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: action.icon)
                            .font(.caption)
                        Text(action.rawValue)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Custom").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Or type a prompt…", text: $customDraft, onCommit: runCustom)
                    .textFieldStyle(.roundedBorder)
                    .focused($customFocused)
                    .onSubmit(runCustom)
                Button {
                    runCustom()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(customDraft.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(customDraft.isEmpty)
            }
        }
    }

    private var processingState: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(UICopy.Status.drafting)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func runCustom() {
        let trimmed = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let promptBase = "You are a writing assistant. Apply this instruction to the user's text"
            + " and output only the rewritten text — no preamble. Instruction: "
        let prompt = promptBase + trimmed
        controller.run(action: .simplify, customPrompt: prompt)
    }
}
