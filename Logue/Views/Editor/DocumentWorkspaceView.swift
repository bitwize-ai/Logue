import AppKit
import SwiftUI
import Textual

// MARK: - DocumentWorkspaceView

/// Full document editor: top bar, centered editor, right tool panel + icon toolbar.
/// Lives inside the detail pane of the unified NavigationSplitView.
struct DocumentWorkspaceView: View {
    // Extension-visible: +Toolbar
    @Environment(DocumentStore.self) var store
    @Environment(ModelManager.self) private var modelManager
    @Environment(TemplateStore.self) private var templateStore
    @Environment(\.colorScheme) private var colorScheme

    // Analysis state
    @State private var spellSuggestions: [Suggestion] = []
    @State private var llmSuggestions: [Suggestion] = []
    private var suggestions: [Suggestion] {
        (spellSuggestions + llmSuggestions)
            .sorted { $0.textRange.location < $1.textRange.location }
    }

    @State private var isAnalyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var spellDebounceTask: Task<Void, Never>?
    @State private var spellEngine = InlineSpellEngine()
    @State private var cursorOffset: Int = 0
    @State private var errorMessage: String?
    /// Prevents spell check re-trigger when programmatically applying a suggestion
    @State private var isApplyingSuggestion = false
    /// Tracks which character ranges have been spell-checked (avoids redundant checks).
    @State private var checkedSpellRanges: [NSRange] = []
    /// UI state
    @State private var activeTool: EditorTool? = .aiChat
    // Extension-visible: +Toolbar
    @State var showWordCount = true
    @State private var chatMessages: [ChatMessage] = []
    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @State private var aiChatPendingMessage: String?
    // Extension-visible: +Toolbar
    @State var isSidebarCollapsed = false
    @State private var scrollToSuggestion: Suggestion?
    /// Scrolls to and selects arbitrary text in the editor (used by vocab enhancement, etc.)
    @State private var scrollToText: String?
    @State private var toolPanelWidths: [String: CGFloat] = [:]
    // Extension-visible: +Toolbar
    @State var showTagPopover = false
    @State private var newTagText = ""
    // Extension-visible: +Toolbar
    @State var showRenameAlert = false
    // Extension-visible: +Toolbar
    @State var renameText = ""
    // Extension-visible: +Toolbar
    @State var titleGenerationTask: Task<Void, Never>?
    @State private var hasTriggeredAutoTitle = false
    @FocusState private var isTagFieldFocused: Bool
    // Extension-visible: +Toolbar
    @State var showSaveAsTemplate = false

    // Extension-visible: +Toolbar
    @State var focusState = FocusModeState.shared
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        if let doc = store.selectedDocument {
            HStack(spacing: 0) {
                // Center: rich text editor
                VStack(spacing: 0) {
                    if !focusState.isActive,
                       let sourceMeeting = meetingStore.meetingLinked(toDocument: doc.id)
                    {
                        SourceMeetingChip(meeting: sourceMeeting) {
                            meetingStore.selectedMeetingID = sourceMeeting.id
                        }
                    }

                    BlockEditorView(
                        markdownText: documentBodyBinding(doc: doc),
                        suggestions: suggestions,
                        fontSize: fontSize,
                        onCursorPositionChange: { cursorOffset = $0 },
                        onSuggestionAccepted: { acceptFromEditor(suggestion: $0) },
                        onSuggestionDismissed: { dismiss(suggestion: $0) },
                        scrollToSuggestion: $scrollToSuggestion,
                        scrollToText: $scrollToText
                    )
                    .frame(maxWidth: focusState.isActive ? focusState.columnWidth : .infinity)
                    .frame(maxWidth: .infinity)

                    if !focusState.isActive {
                        Divider()
                        WritingStatsBarView(
                            text: doc.body,
                            isAnalyzing: isAnalyzing,
                            errorMessage: errorMessage
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                // Right: unified sidebar (hidden in focus mode)
                if !focusState.isActive {
                    UnifiedSidebarView(
                        activeTool: $activeTool,
                        isCollapsed: $isSidebarCollapsed,
                        panelWidths: $toolPanelWidths
                    ) { tool in
                        rightPanel(for: tool, doc: doc)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(AppThemeConstants.contentBackground)
            .navigationTitle(doc.title)
            .navigationSubtitle(focusState.isActive ? "\(doc.wordCount) words · Focus Mode" : "\(doc.wordCount) words")
            .toolbar {
                if focusState.isActive {
                    focusModeToolbarContent
                } else {
                    documentToolbarContent(doc: doc)
                }
            }
            .onKeyPress(.escape) {
                if focusState.isActive {
                    focusState.exit()
                    return .handled
                }
                return .ignored
            }
            .onChange(of: isSidebarCollapsed) { _, collapsed in
                if !collapsed, activeTool == nil {
                    activeTool = .proofreader
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .logueAskAI)) { note in
                aiChatPendingMessage = note.object as? String
                isSidebarCollapsed = false
                activeTool = .aiChat
            }
            .id(doc.id)
            .onAppear { chatMessages = doc.chatMessages; triggerInitialAnalysis(for: doc) }
            .onDisappear {
                // U4: Cancel in-flight tasks on document switch
                analysisTask?.cancel()
                spellDebounceTask?.cancel()
                titleGenerationTask?.cancel()
                store.setChatMessages(chatMessages, for: doc.id)
            }
            .sheet(isPresented: $showSaveAsTemplate) {
                SaveAsTemplateSheet(document: doc)
                    .environment(templateStore)
            }
        }
    }

    // MARK: - Right Panel Router

    @ViewBuilder
    private func rightPanel(for tool: EditorTool, doc: WritingDocument) -> some View {
        switch tool {
        case .aiChat:
            aiChatPanel(doc: doc)
        case .proofreader:
            SuggestionPanelView(
                suggestions: suggestions, isAnalyzing: isAnalyzing,
                onAccept: { accept(suggestion: $0, in: doc) },
                onDismiss: { dismiss(suggestion: $0) },
                onAcceptAll: { acceptAll(in: doc) },
                onSuggestionSelected: { scrollToSuggestion = $0 }
            )
        case .rewrite:
            RewritePanelView(
                document: doc,
                onApply: { applyBody($0, to: doc) },
                onResultSave: { store.setRewriteResult($0, for: doc.id) }
            )
        case .review:
            reviewPanel(doc: doc)
        case .verify:
            VerifyPanelView(
                document: doc,
                onFactChecksSave: { store.setFactChecks($0, for: doc.id) },
                onPIIFindingsSave: { store.setPIIFindings($0, for: doc.id) },
                onAIDetectionSave: { result in
                    // Phase H: serialize the full DetectorResult to the
                    // existing String? field so the breakdown re-renders
                    // on next launch without re-scoring.
                    let encoded = result
                        .flatMap { try? JSONEncoder().encode($0) }
                        .flatMap { String(data: $0, encoding: .utf8) }
                    store.setAIDetectionResult(encoded, for: doc.id)
                }
            )
        case .vocabularyEnhancement:
            VocabularyEnhancementPanelView(
                document: doc,
                onReplace: { original, replacement in
                    var updated = doc
                    // Case-insensitive search — LLM may return different casing
                    guard let range = updated.body.range(
                        of: original, options: .caseInsensitive
                    )
                    else { return false }
                    updated.body.replaceSubrange(range, with: replacement)
                    store.updateDocument(updated)
                    return true
                },
                onScrollToText: { scrollToText = $0 },
                onSuggestionsSave: { store.setVocabSuggestions($0, for: doc.id) }
            )
        }
    }

    private func aiChatPanel(doc: WritingDocument) -> some View {
        AIChatPanelView(
            document: doc,
            onSave: { store.setChatMessages(chatMessages, for: doc.id) },
            messages: $chatMessages,
            pendingMessage: $aiChatPendingMessage,
            onInsert: { content in
                var updated = doc
                let sep = updated.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
                updated.body += sep + content
                store.updateDocument(updated)
            }
        )
    }

    private func reviewPanel(doc: WritingDocument) -> some View {
        ReviewPanelView(
            document: doc,
            onRunLLMAnalysis: { runAnalysis(for: doc) },
            onCancelLLMAnalysis: { cancelAnalysis() },
            onGoalModeChanged: { mode in
                var updated = doc
                updated.goalMode = mode
                store.updateDocument(updated)
            },
            isLLMAnalyzing: isAnalyzing,
            onGradeSave: { store.setReviewGrade($0, for: doc.id) },
            onReactionsSave: { store.setReviewReactions($0, for: doc.id) }
        )
    }

    private func applyBody(_ newBody: String, to doc: WritingDocument) {
        var updated = doc
        updated.body = newBody
        store.updateDocument(updated)
    }

    // MARK: - Analysis

    private func triggerInitialAnalysis(for doc: WritingDocument) {
        guard !doc.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAnalyzing = true; analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(for: AppConstants.Delays.spellCheckDebounce)
            guard !Task.isCancelled else { return }; runAnalysis(for: doc)
        }
    }

    private func runAnalysis(for doc: WritingDocument) {
        guard !doc.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Re-check focused area; preserve spell suggestions outside the window
        checkedSpellRanges.removeAll()
        let window = spellEngine.windowRange(for: doc.body, cursorOffset: cursorOffset)
        let outsideWindow = spellSuggestions.filter { NSIntersectionRange($0.textRange, window).length == 0 }
        let freshInWindow = spellEngine.checkFocused(doc.body, cursorOffset: cursorOffset)
        spellSuggestions = outsideWindow + freshInWindow
        markSpellChecked(window)

        // Clear previous LLM suggestions — fresh analysis
        llmSuggestions.removeAll()

        analysisTask?.cancel()
        errorMessage = nil
        isAnalyzing = true

        analysisTask = Task {
            do {
                // C8: Removed redundant await MainActor.run — Task already inherits @MainActor
                let state = try await WritingAgentGraph.shared.analyze(
                    text: doc.body,
                    cursorOffset: cursorOffset,
                    goalMode: doc.goalMode
                )
                guard !Task.isCancelled else { return }
                let newSuggestions = state.allSuggestions.map { $0.toDomain() }
                let score = WritingScore.compute(
                    grammarCount: state.grammarSuggestions?.count ?? 0,
                    clarityCount: state.claritySuggestions?.count,
                    wordCount: state.wordCount ?? 0
                )
                appendResolvedSuggestions(newSuggestions, body: doc.body)
                isAnalyzing = false
                let docID = doc.id
                if var fresh = store.documents.first(where: { $0.id == docID }) {
                    fresh.score = score
                    store.updateDocument(fresh)
                }
            } catch {
                errorMessage = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    /// Resolves textRange for each suggestion by searching `body`, then appends to `llmSuggestions`.
    private func appendResolvedSuggestions(_ newSuggestions: [Suggestion], body: String) {
        let nsBody = body as NSString
        let existingOriginals = Set(llmSuggestions.map(\.original))
        var usedLocations = Set<Int>()
        for var suggestion in newSuggestions {
            guard !existingOriginals.contains(suggestion.original) else { continue }
            var searchStart = 0
            while searchStart < nsBody.length {
                let searchRange = NSRange(location: searchStart, length: nsBody.length - searchStart)
                let found = nsBody.range(of: suggestion.original, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                if !usedLocations.contains(found.location) {
                    suggestion.textRange = found
                    usedLocations.insert(found.location)
                    break
                }
                searchStart = found.location + 1
            }
            llmSuggestions.append(suggestion)
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        Task { await LLMEngine.shared.cancelAnalysis() }
        isAnalyzing = false
    }

    // MARK: - Suggestion Actions

    private func accept(suggestion: Suggestion, in doc: WritingDocument) {
        guard suggestion.original != suggestion.replacement else {
            dismiss(suggestion: suggestion)
            return
        }
        isApplyingSuggestion = true
        var updated = doc
        let nsBody = updated.body as NSString

        // Use textRange to find the correct occurrence (not just the first)
        var swiftRange: Range<String.Index>?
        if suggestion.textRange.location != NSNotFound,
           NSMaxRange(suggestion.textRange) <= nsBody.length
        {
            // Verify the text at textRange still matches
            let textAtRange = nsBody.substring(with: suggestion.textRange)
            if textAtRange == suggestion.original {
                swiftRange = Range(suggestion.textRange, in: updated.body)
            }
        }
        // Fallback: search for first occurrence if textRange is stale or unresolved
        if swiftRange == nil {
            swiftRange = updated.body.range(of: suggestion.original)
        }

        if let range = swiftRange {
            updated.body.replaceSubrange(range, with: suggestion.replacement)
            store.updateDocument(updated)
        }

        // Invalidate checked ranges near the replacement site
        invalidateSpellRanges(around: suggestion.textRange.location)

        // Only remove suggestions that directly overlap with the replaced range
        let replacedRange = suggestion.textRange
        spellSuggestions.removeAll { existing in
            guard existing.id != suggestion.id else { return false }
            let existingEnd = NSMaxRange(existing.textRange)
            let replacedEnd = NSMaxRange(replacedRange)
            return existing.textRange.location < replacedEnd && replacedRange.location < existingEnd
        }

        // Adjust text ranges of remaining suggestions after the replacement
        let lengthDiff = (suggestion.replacement as NSString).length - (suggestion.original as NSString).length
        adjustSuggestionRanges(after: replacedRange, lengthDiff: lengthDiff)

        dismiss(suggestion: suggestion)
        isApplyingSuggestion = false
    }

    /// Called when a suggestion is accepted via the inline editor popover.
    /// The text replacement already happened in the NSTextView — just adjust
    /// remaining suggestion ranges and remove the accepted one.
    private func acceptFromEditor(suggestion: Suggestion) {
        let replacedRange = suggestion.textRange

        // Only adjust ranges if the replaced range is valid
        if replacedRange.location != NSNotFound {
            let lengthDiff = (suggestion.replacement as NSString).length - (suggestion.original as NSString).length
            adjustSuggestionRanges(after: replacedRange, lengthDiff: lengthDiff)
        }

        invalidateSpellRanges(around: suggestion.textRange.location)
        dismiss(suggestion: suggestion)
    }

    private func dismiss(suggestion: Suggestion) {
        spellSuggestions.removeAll { $0.id == suggestion.id }
        llmSuggestions.removeAll { $0.id == suggestion.id }
    }

    /// Applies all current suggestions at once by iterating from end-to-start
    /// (descending by textRange.location) to avoid offset invalidation.
    private func acceptAll(in doc: WritingDocument) {
        guard !suggestions.isEmpty else { return }
        isApplyingSuggestion = true
        var updated = doc
        let nsBody = updated.body as NSString

        // Build verified (range, replacement) pairs
        var replacements: [(range: NSRange, replacement: String)] = []
        for suggestion in suggestions {
            guard suggestion.original != suggestion.replacement else { continue }
            var range = suggestion.textRange
            if range.location != NSNotFound,
               NSMaxRange(range) <= nsBody.length
            {
                let textAtRange = nsBody.substring(with: range)
                if textAtRange != suggestion.original {
                    let resolved = nsBody.range(of: suggestion.original, options: .literal)
                    guard resolved.location != NSNotFound else { continue }
                    range = resolved
                }
            } else {
                let resolved = nsBody.range(of: suggestion.original, options: .literal)
                guard resolved.location != NSNotFound else { continue }
                range = resolved
            }
            replacements.append((range, suggestion.replacement))
        }

        // Sort descending by location — later replacements first to preserve earlier offsets
        replacements.sort { $0.range.location > $1.range.location }

        // Apply all replacements from end to start
        for item in replacements {
            if let swiftRange = Range(item.range, in: updated.body) {
                updated.body.replaceSubrange(swiftRange, with: item.replacement)
            }
        }

        store.updateDocument(updated)

        // Clear all suggestions and reset spell check coverage
        spellSuggestions.removeAll()
        llmSuggestions.removeAll()
        checkedSpellRanges.removeAll()

        isApplyingSuggestion = false
    }

    /// Shifts suggestion ranges that come after a replacement site.
    private func adjustSuggestionRanges(after replacedRange: NSRange, lengthDiff: Int) {
        for i in spellSuggestions.indices where spellSuggestions[i].textRange.location >= NSMaxRange(replacedRange) {
            spellSuggestions[i].textRange.location += lengthDiff
        }
        for i in llmSuggestions.indices where llmSuggestions[i].textRange.location >= NSMaxRange(replacedRange) {
            llmSuggestions[i].textRange.location += lengthDiff
        }
    }
}

// MARK: - Spell Range Tracking & Bindings

extension DocumentWorkspaceView {
    private func markSpellChecked(_ range: NSRange) {
        guard range.length > 0 else { return }
        var merged = range
        checkedSpellRanges.removeAll { existing in
            if NSIntersectionRange(existing, merged).length > 0
                || NSMaxRange(existing) == merged.location
                || NSMaxRange(merged) == existing.location
            {
                let lo = min(existing.location, merged.location)
                let hi = max(NSMaxRange(existing), NSMaxRange(merged))
                merged = NSRange(location: lo, length: hi - lo)
                return true
            }
            return false
        }
        checkedSpellRanges.append(merged)
    }

    private func invalidateSpellRanges(around editOffset: Int, radius: Int = 200) {
        let lo = max(0, editOffset - radius)
        let hi = editOffset + radius
        let zone = NSRange(location: lo, length: hi - lo)

        var updated: [NSRange] = []
        for range in checkedSpellRanges {
            if NSIntersectionRange(range, zone).length == 0 {
                updated.append(range)
            } else {
                if range.location < zone.location {
                    updated.append(NSRange(location: range.location, length: zone.location - range.location))
                }
                if NSMaxRange(range) > NSMaxRange(zone) {
                    let afterStart = NSMaxRange(zone)
                    updated.append(NSRange(location: afterStart, length: NSMaxRange(range) - afterStart))
                }
            }
        }
        checkedSpellRanges = updated
    }

    private func isSpellFullyCovered(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return true }
        for checked in checkedSpellRanges {
            if checked.location <= range.location, NSMaxRange(checked) >= NSMaxRange(range) {
                return true
            }
        }
        return false
    }

    private func submitTag(to documentID: UUID) {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addTag(trimmed, to: documentID)
        newTagText = ""
    }

    private func documentBodyBinding(doc: WritingDocument) -> Binding<String> {
        Binding(
            get: { doc.body },
            set: { newText in
                let docID = doc.id
                guard var updated = store.documents.first(where: { $0.id == docID }) else { return }
                updated.body = newText
                store.updateDocument(updated)

                // Remove LLM suggestions whose original text no longer exists
                llmSuggestions.removeAll { suggestion in
                    !newText.contains(suggestion.original)
                }

                // Only run spell check for user edits, not when applying a suggestion
                if !isApplyingSuggestion {
                    spellDebounceTask?.cancel()
                    let offset = cursorOffset

                    // Invalidate checked ranges near the edit point
                    invalidateSpellRanges(around: offset)

                    // Remove existing suggestions in the invalidated zone
                    let zone = NSRange(location: max(0, offset - 200), length: 400)
                    spellSuggestions.removeAll { NSIntersectionRange($0.textRange, zone).length > 0 }

                    let capturedDocID = docID
                    spellDebounceTask = Task {
                        try? await Task.sleep(for: AppConstants.Delays.spellCheckDebounce)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            // Re-fetch fresh document text + cursor (may have changed during debounce)
                            let freshOffset = cursorOffset
                            guard let freshText = store.documents.first(where: { $0.id == capturedDocID })?.body else { return }
                            let window = spellEngine.windowRange(for: freshText, cursorOffset: freshOffset)

                            // Skip if this window is already fully checked
                            guard !isSpellFullyCovered(window) else { return }

                            // Check the focused window + mark as checked
                            let newSuggestions = spellEngine.checkFocused(freshText, cursorOffset: freshOffset)
                            markSpellChecked(window)

                            // Merge — add only non-duplicates
                            for suggestion in newSuggestions {
                                let isDupe = spellSuggestions.contains {
                                    $0.textRange == suggestion.textRange && $0.original == suggestion.original
                                }
                                if !isDupe {
                                    spellSuggestions.append(suggestion)
                                }
                            }
                        }
                    }
                }

                if !hasTriggeredAutoTitle,
                   updated.title == "Untitled Document",
                   newText.trimmingCharacters(in: .whitespacesAndNewlines).count > 50
                {
                    hasTriggeredAutoTitle = true
                    titleGenerationTask?.cancel()
                    titleGenerationTask = Task {
                        try? await Task.sleep(for: AppConstants.Delays.documentAutoTitleDebounce)
                        guard !Task.isCancelled else { return }
                        await store.generateAITitle(for: docID)
                    }
                }
            }
        )
    }
}

// MARK: - Export & Tag Helpers

extension DocumentWorkspaceView {
    func exportAsMarkdown(doc: WritingDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(doc.title).md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.body.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func tagPopoverContent(doc: WritingDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !doc.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(doc.tags, id: \.self) { tag in
                        FilterChip(label: tag, style: .removable, tintColor: AppThemeConstants.tagColor(for: tag)) {
                            store.removeTag(tag, from: doc.id)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add tag…", text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isTagFieldFocused)
                    .onSubmit { submitTag(to: doc.id) }

                if !newTagText.isEmpty {
                    Button { submitTag(to: doc.id) } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppThemeConstants.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add tag")
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))

            tagSuggestions(for: doc)
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { isTagFieldFocused = true }
    }

    @ViewBuilder
    func tagSuggestions(for doc: WritingDocument) -> some View {
        let suggestions = store.allTags.filter {
            !newTagText.isEmpty
                && $0.localizedCaseInsensitiveContains(newTagText)
                && !doc.tags.contains($0)
        }
        if !suggestions.isEmpty {
            HStack(spacing: 4) {
                ForEach(suggestions.prefix(5), id: \.self) { suggestion in
                    let color = AppThemeConstants.tagColor(for: suggestion)
                    Button {
                        store.addTag(suggestion, to: doc.id)
                        newTagText = ""
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(AppThemeConstants.opacityLight), in: Capsule())
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
