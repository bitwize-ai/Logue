import SwiftUI

// MARK: - Block Frame Preference Key

/// Collects each block's frame in the scroll coordinate space for drag hit-testing.
private struct BlockFramePreferenceKey: PreferenceKey {
    static var defaultValue: [BlockID: CGRect] = [:]
    static func reduce(value: inout [BlockID: CGRect], nextValue: () -> [BlockID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - BlockEditorView

/// Top-level SwiftUI view for the block-based editor.
/// Renders an ordered list of blocks in a scrollable vertical stack.
struct BlockEditorView: View {
    @Binding var markdownText: String
    var suggestions: [Suggestion] = []
    var fontSize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize
    var onCursorPositionChange: ((Int) -> Void)?
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?
    @Binding var scrollToSuggestion: Suggestion?
    /// Scrolls to and selects arbitrary text (used by vocab enhancement, etc.)
    @Binding var scrollToText: String?

    @Environment(\.undoManager) private var undoManager
    @State private var document = BlockEditorDocument()
    @State private var focusedBlockID: BlockID?
    @State private var focusedItemID: UUID?
    @State private var pendingCursorOffset: Int?
    @State private var isLoaded = false
    /// The last markdown string we synced from blocks → binding.
    /// Used to prevent re-parsing our own output when the binding round-trips.
    @State private var lastSyncedMarkdown: String?
    @State private var selectionToolbarPosition: CGPoint?
    @State private var activeTextView: MarkdownNSTextView?
    @State private var activeSelectionRange: NSRange?
    @State private var syncTask: Task<Void, Never>?
    /// Set this to a block ID to programmatically scroll to it.
    /// Only used for explicit scroll requests (e.g., sidebar suggestion clicks).
    @State private var programmaticFocusTarget: BlockID?
    /// Cached suggestion map — recomputed only when suggestions or blocks change.
    @State private var cachedSuggestionsByBlock: [BlockID: [Suggestion]] = [:]
    /// Briefly highlights a block after programmatic scroll to draw attention.
    @State private var highlightedBlockID: BlockID?
    /// When set, the matching BlockTextView selects the suggestion's original text range.
    @State private var highlightedSuggestionID: UUID?
    /// Per-block cleanup tasks for temporary suggestions injected by `scrollToBlockContaining`.
    /// Keyed by block ID so rapid scrolls to different blocks don't orphan earlier cleanup tasks.
    @State private var suggestionCleanupTasks: [BlockID: Task<Void, Never>] = [:]

    // MARK: - Multi-Block Selection State

    @State private var multiBlockSelection = MultiBlockSelectionState()
    @State private var blockFrames: [BlockID: CGRect] = [:]
    @State private var dragMonitor: Any?
    @State private var mouseUpMonitor: Any?
    @State private var isDraggingAcrossBlocks = false
    /// Reference to the key handler view so we can make it first responder.
    @State private var keyHandlerView: KeyHandlerNSView?
    /// Desired cursor X position for arrow key navigation across blocks.
    @State private var pendingCursorXPosition: CGFloat?
    /// Persistent goal column X for vertical arrow navigation.
    /// Set on first up/down press, preserved across block boundaries, reset on horizontal movement/click/type.
    @State private var goalColumnX: CGFloat?

    // MARK: - In-Document Search

    @State private var searchState = DocumentSearchState()
    @State private var findMonitor: Any?

    // MARK: - Inline Rewrite

    @State private var rewriteState = InlineRewriteState()
    @State private var rewriteShortcutMonitor: Any?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(document.blocks) { block in
                                blockRow(for: block, geometry: geometry)
                                    .background(
                                        GeometryReader { blockGeo in
                                            Color.clear.preference(
                                                key: BlockFramePreferenceKey.self,
                                                value: [block.id: blockGeo.frame(in: .named("editorScroll"))]
                                            )
                                        }
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                AppThemeConstants.brandPrimary
                                                    .opacity(highlightedBlockID == block.id ? 0.6 : 0),
                                                lineWidth: 2
                                            )
                                            .animation(.easeInOut(duration: 0.3), value: highlightedBlockID)
                                    )
                                    .id(block.id)
                            }
                        }
                        .padding(.horizontal, AppThemeConstants.editorHorizontalInset)
                        .padding(.vertical, AppThemeConstants.editorVerticalInset)
                    }
                    .coordinateSpace(name: "editorScroll")
                    .onPreferenceChange(BlockFramePreferenceKey.self) { newFrames in
                        blockFrames = newFrames
                    }
                    .onScrollPhaseChange { _, newPhase in
                        // Dismiss floating selection toolbar when scrolling starts
                        if newPhase != .idle, selectionToolbarPosition != nil {
                            selectionToolbarPosition = nil
                        }
                        // Dismiss inline rewrite popover on scroll so it doesn't
                        // float orphaned when the anchored selection leaves the viewport.
                        if newPhase != .idle, rewriteState.isVisible {
                            rewriteState.dismiss()
                        }
                    }
                    .onChange(of: programmaticFocusTarget) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                        highlightedBlockID = newID
                        programmaticFocusTarget = nil
                        // Remove highlight after brief delay
                        Task {
                            try? await Task.sleep(for: AppConstants.Delays.blockHighlight)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.4)) {
                                highlightedBlockID = nil
                            }
                        }
                    }
                }

                // Floating selection toolbar (hidden during multi-block selection
                // or while the inline-rewrite popover is open to avoid stacking).
                if !multiBlockSelection.isActive, !rewriteState.isVisible,
                   let toolbarPos = selectionToolbarPosition
                {
                    SelectionToolbarView(
                        formattingState: FormattingState(),
                        onAction: { action in
                            handleFormattingAction(action)
                        }
                    )
                    .focusable(false)
                    .fixedSize()
                    .position(x: toolbarPos.x, y: toolbarPos.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Inline rewrite popover (anchored at the selection's original position).
                if rewriteState.isVisible {
                    InlineRewritePopover(state: rewriteState)
                        .fixedSize()
                        .position(
                            x: rewriteState.anchorPosition.x,
                            y: rewriteState.anchorPosition.y
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(100)
                }

                // Invisible key handler for multi-block selection keyboard shortcuts
                if multiBlockSelection.isActive {
                    MultiBlockKeyHandler(
                        onCopy: { copySelectedBlocks() },
                        onCut: { cutSelectedBlocks() },
                        onDelete: { deleteSelectedBlocks() },
                        onSelectAll: { multiBlockSelection.selectAll(blocks: document.blocks) },
                        onEscape: { clearMultiBlockSelection() },
                        onTyping: { _ in
                            // Clear selection and type into first selected block
                            let firstID = document.blocks.first(where: {
                                multiBlockSelection.selectedBlockIDs.contains($0.id)
                            })?.id
                            clearMultiBlockSelection()
                            if let firstID {
                                focusedBlockID = firstID
                                pendingCursorOffset = 0
                            }
                        }
                    )
                    .frame(width: 0, height: 0)
                    .onAppear {
                        // Make the key handler first responder
                        DispatchQueue.main.async {
                            if let window = NSApp.keyWindow,
                               let keyView = findKeyHandlerView(in: window.contentView)
                            {
                                window.makeFirstResponder(keyView)
                            }
                        }
                    }
                }

                // Floating search bar (Cmd+F)
                if searchState.isActive {
                    VStack {
                        HStack {
                            Spacer()
                            DocumentSearchBar(searchState: searchState) {
                                navigateToCurrentMatch(proxy: nil)
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            guard !isLoaded else { return }
            document.undoManager = undoManager
            document.loadFromMarkdown(markdownText)
            isLoaded = true
            focusedBlockID = document.blocks.first?.id
            cachedSuggestionsByBlock = buildSuggestionMap(suggestions)
            installDragMonitor()
            installFindMonitor()
            installRewriteShortcutMonitor()
        }
        // U1: Merged dual .onDisappear into the single one at line ~283
        .onChange(of: searchState.query) { _, _ in
            searchState.search(in: document.blocks)
        }
        .onChange(of: searchState.matchCase) { _, _ in
            searchState.search(in: document.blocks)
        }
        .onChange(of: searchState.wholeWord) { _, _ in
            searchState.search(in: document.blocks)
        }
        .onChange(of: searchState.isActive) { _, active in
            if !active {
                searchState.query = ""
                searchState.matches = []
                searchState.currentMatchIndex = 0
            }
        }
        .onChange(of: undoManager) { _, newManager in
            document.undoManager = newManager
        }
        .onChange(of: markdownText) { _, newValue in
            // Only re-parse if the change came from outside (not from our own edits)
            guard isLoaded else { return }
            // Skip if this value is what we just synced from blocks
            if newValue == lastSyncedMarkdown {
                return
            }
            let currentMarkdown = document.toMarkdown()
            if currentMarkdown != newValue {
                document.loadFromMarkdown(newValue)
            }
        }
        .onChange(of: document.blocks) { _, _ in
            debouncedSyncMarkdown()
            cachedSuggestionsByBlock = buildSuggestionMap(suggestions)
        }
        .onChange(of: document.tableChangeCounter) { _, _ in
            debouncedSyncMarkdown()
        }
        .onChange(of: suggestions.map(\.id)) { _, _ in
            cachedSuggestionsByBlock = buildSuggestionMap(suggestions)
        }
        .onChange(of: scrollToSuggestion?.id) { _, _ in
            guard let suggestion = scrollToSuggestion else { return }
            // First try: look in the cached suggestion map (fast path for proofreader suggestions)
            var found = false
            for (blockID, blockSuggestions) in cachedSuggestionsByBlock where blockSuggestions.contains(where: { $0.id == suggestion.id }) {
                focusedBlockID = blockID
                programmaticFocusTarget = blockID
                highlightedSuggestionID = suggestion.id
                found = true
                break
            }
            // Fallback: search block text for the suggestion's original string (vocab enhancement, etc.)
            if !found {
                scrollToBlockContaining(text: suggestion.original)
            }
            scrollToSuggestion = nil
        }
        .onChange(of: scrollToText) { _, newText in
            guard let text = newText else { return }
            scrollToBlockContaining(text: text)
            scrollToText = nil
        }
        .onChange(of: focusedBlockID) { _, _ in
            // Clear multi-block selection when user clicks into a specific block
            if multiBlockSelection.isActive, !isDraggingAcrossBlocks {
                clearMultiBlockSelection()
            }
        }
        // U1: Single merged onDisappear — includes findMonitor cleanup
        .onDisappear {
            if let findMonitor {
                NSEvent.removeMonitor(findMonitor)
            }
            findMonitor = nil
            if let rewriteShortcutMonitor {
                NSEvent.removeMonitor(rewriteShortcutMonitor)
            }
            rewriteShortcutMonitor = nil
            rewriteState.dismiss()
            syncTask?.cancel()
            flushTemporarySuggestions()
            syncMarkdownFromBlocks()
            removeDragMonitor()
        }
    }

    // MARK: - Selection Change Handler

    private func handleSelectionChange(
        textView: MarkdownNSTextView,
        range: NSRange,
        contentViewRect: CGRect?,
        block: Block,
        geometry: GeometryProxy
    ) {
        if range.length > 0, let rect = contentViewRect {
            activeTextView = textView
            activeSelectionRange = range
            let globalFrame = geometry.frame(in: .global)
            // Convert content-view coords to local GeometryReader coords
            let localX = rect.midX - globalFrame.minX
            let localY = rect.minY - globalFrame.minY
            // Position toolbar above the selection (offset by toolbar height)
            selectionToolbarPosition = CGPoint(
                x: localX,
                y: localY - 30
            )
        } else {
            selectionToolbarPosition = nil
            activeTextView = nil
            activeSelectionRange = nil
        }

        // Report global cursor offset for focused spell/analysis
        let blockIndex = document.blocks.firstIndex(where: { $0.id == block.id }) ?? 0
        var globalOffset = 0
        for idx in 0 ..< blockIndex {
            globalOffset += BlockSerializer.serializeBlock(document.blocks[idx]).count
            globalOffset += 2 // \n\n separator between blocks
        }
        // Add approximate prefix for the current block
        switch document.blocks[blockIndex] {
        case let .heading(_, level, _):
            globalOffset += level + 1 // "## " etc.
        case .blockQuote:
            globalOffset += 2 // "> "
        case let .codeBlock(_, lang, _):
            globalOffset += 3 + lang.count + 1 // "```lang\n"
        case .bulletList, .numberedList:
            globalOffset += 2 // "- "
        case .checkboxList:
            globalOffset += 6 // "- [ ] "
        default:
            break
        }
        globalOffset += range.location
        onCursorPositionChange?(globalOffset)
    }

    // MARK: - Markdown Sync

    private func debouncedSyncMarkdown() {
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: AppConstants.Delays.markdownSyncDebounce)
            guard !Task.isCancelled else { return }
            syncMarkdownFromBlocks()
        }
    }

    private func syncMarkdownFromBlocks() {
        guard isLoaded else { return }
        let newMarkdown = document.toMarkdown()
        if newMarkdown != markdownText {
            lastSyncedMarkdown = newMarkdown
            markdownText = newMarkdown
        }
    }

    // MARK: - Formatting

    private func handleFormattingAction(_ action: FormattingAction) {
        guard let textView = activeTextView else { return }
        // Ensure text view is first responder (toolbar click may have shifted focus)
        textView.window?.makeFirstResponder(textView)
        switch action {
        case .bold:
            textView.applyMarkdownFormatting("**")
        case .italic:
            textView.applyMarkdownFormatting("*")
        case .strikethrough:
            textView.applyMarkdownFormatting("~~")
        case .inlineCode:
            textView.applyMarkdownFormatting("`")
        case .underline:
            // Markdown doesn't have underline — use HTML tag
            textView.applyMarkdownFormatting("<u>")
        case .link:
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let selected = (textView.string as NSString).substring(with: range)
            let linked = "[\(selected)](url)"
            textView.insertText(linked, replacementRange: range)
        case .copySelection:
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let selected = (textView.string as NSString).substring(with: range)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selected, forType: .string)
        case .askAI:
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let selected = (textView.string as NSString).substring(with: range)
            NotificationCenter.default.post(name: .logueAskAI, object: selected)
        case .rewrite:
            beginInlineRewrite(textView: textView)
        }
        selectionToolbarPosition = nil
    }

    /// Cancels all per-block cleanup tasks and removes any remaining temporary suggestions from the cache.
    private func flushTemporarySuggestions() {
        for (_, task) in suggestionCleanupTasks {
            task.cancel()
        }
        suggestionCleanupTasks.removeAll()
        let nsNotFound = NSNotFound
        for blockID in cachedSuggestionsByBlock.keys {
            cachedSuggestionsByBlock[blockID]?.removeAll { $0.textRange.location == nsNotFound }
        }
    }

    // MARK: - Scroll to Text

    /// Searches all blocks for the given text and scrolls/highlights the matching block.
    /// Also sets `highlightedSuggestionID` with a temporary suggestion so BlockTextView selects the range.
    private func scrollToBlockContaining(text: String) {
        for block in document.blocks {
            let blockTexts = block.searchableTexts
            // Search both raw and markdown-stripped text (case-insensitive)
            let found = blockTexts.contains {
                let raw = $0 as NSString
                let stripped = $0.strippingInlineMarkdown as NSString
                return raw.range(of: text, options: .caseInsensitive).location != NSNotFound
                    || stripped.range(of: text, options: .caseInsensitive).location != NSNotFound
            }
            if found {
                focusedBlockID = block.id
                programmaticFocusTarget = block.id
                // Create a temporary suggestion so BlockTextView can select the text range
                let tempID = UUID()
                let tempSuggestion = Suggestion(
                    id: tempID, type: .style, original: text, replacement: text,
                    explanation: "", confidence: 0,
                    textRange: NSRange(location: NSNotFound, length: 0)
                )
                // Temporarily inject into the block's suggestion list for highlighting
                var blockSuggestions = cachedSuggestionsByBlock[block.id] ?? []
                blockSuggestions.append(tempSuggestion)
                cachedSuggestionsByBlock[block.id] = blockSuggestions
                highlightedSuggestionID = tempID
                // Clean up the temporary suggestion after it's consumed (per-block to avoid orphans)
                suggestionCleanupTasks[block.id]?.cancel()
                suggestionCleanupTasks[block.id] = Task { @MainActor in
                    try? await Task.sleep(for: AppConstants.Delays.suggestionHighlightCleanup)
                    guard !Task.isCancelled else { return }
                    cachedSuggestionsByBlock[block.id]?.removeAll { $0.id == tempID }
                    suggestionCleanupTasks[block.id] = nil
                }
                return
            }
        }
    }

    // MARK: - Block Row Builder

    /// Extracted to a separate method to keep the ForEach body simple for the type-checker.
    private func blockRow(for block: Block, geometry: GeometryProxy) -> some View {
        BlockRowView(
            block: block,
            document: document,
            focusedBlockID: $focusedBlockID,
            focusedItemID: $focusedItemID,
            pendingCursorOffset: $pendingCursorOffset,
            pendingCursorXPosition: $pendingCursorXPosition,
            goalColumnX: $goalColumnX,
            fontSize: fontSize,
            suggestions: cachedSuggestionsByBlock[block.id] ?? [],
            onSuggestionAccepted: onSuggestionAccepted,
            onSuggestionDismissed: onSuggestionDismissed,
            onSelectionChange: { (textView: MarkdownNSTextView, range: NSRange, contentViewRect: CGRect?) in
                handleSelectionChange(
                    textView: textView,
                    range: range,
                    contentViewRect: contentViewRect,
                    block: block,
                    geometry: geometry
                )
            },
            highlightedSuggestionID: highlightedSuggestionID,
            onHighlightedSuggestionConsumed: { highlightedSuggestionID = nil },
            isBlockSelected: multiBlockSelection.selectedBlockIDs.contains(block.id),
            onSelectAllBlocks: { handleSelectAllBlocks() },
            onShiftArrowUpAtTop: { handleShiftArrowUp(from: block.id) },
            onShiftArrowDownAtBottom: { handleShiftArrowDown(from: block.id) },
            searchMatches: searchState.matches.filter { $0.blockID == block.id },
            currentSearchMatchID: searchState.currentMatch?.id
        )
    }

    // MARK: - Suggestion Mapping

    /// Builds the block → suggestions map. Called only when suggestions or blocks change.
    private func buildSuggestionMap(_ suggestions: [Suggestion]) -> [BlockID: [Suggestion]] {
        guard !suggestions.isEmpty else { return [:] }
        var map: [BlockID: [Suggestion]] = [:]
        for block in document.blocks {
            let textsToSearch = block.searchableTexts
            guard !textsToSearch.isEmpty else { continue }

            let matched = suggestions.filter { suggestion in
                textsToSearch.contains { text in
                    (text as NSString).range(of: suggestion.original).location != NSNotFound
                }
            }
            if !matched.isEmpty {
                map[block.id] = matched
            }
        }
        return map
    }
}

// MARK: - Multi-Block Selection

extension BlockEditorView {
    /// Selects all blocks in the document.
    private func handleSelectAllBlocks() {
        multiBlockSelection.selectAll(blocks: document.blocks)
        multiBlockSelection.anchorBlockID = focusedBlockID
        selectionToolbarPosition = nil
    }

    /// Extends selection upward from the given block.
    private func handleShiftArrowUp(from blockID: BlockID) {
        guard let idx = document.index(of: blockID), idx > 0 else { return }

        if !multiBlockSelection.isActive {
            // Start multi-block selection from current block + previous
            multiBlockSelection.anchorBlockID = blockID
            multiBlockSelection.selectedBlockIDs = [blockID, document.blocks[idx - 1].id]
        } else {
            // Extend: find the topmost selected block and add one above
            let topIdx = document.blocks.indices.first(where: {
                multiBlockSelection.selectedBlockIDs.contains(document.blocks[$0].id)
            }) ?? idx
            if topIdx > 0 {
                multiBlockSelection.selectedBlockIDs.insert(document.blocks[topIdx - 1].id)
            }
        }
        selectionToolbarPosition = nil
    }

    /// Extends selection downward from the given block.
    private func handleShiftArrowDown(from blockID: BlockID) {
        guard let idx = document.index(of: blockID), idx + 1 < document.blocks.count else { return }

        if !multiBlockSelection.isActive {
            // Start multi-block selection from current block + next
            multiBlockSelection.anchorBlockID = blockID
            multiBlockSelection.selectedBlockIDs = [blockID, document.blocks[idx + 1].id]
        } else {
            // Extend: find the bottommost selected block and add one below
            let bottomIdx = document.blocks.indices.reversed().first(where: {
                multiBlockSelection.selectedBlockIDs.contains(document.blocks[$0].id)
            }) ?? idx
            if bottomIdx + 1 < document.blocks.count {
                multiBlockSelection.selectedBlockIDs.insert(document.blocks[bottomIdx + 1].id)
            }
        }
        selectionToolbarPosition = nil
    }

    /// Clears multi-block selection and restores normal editing.
    private func clearMultiBlockSelection() {
        multiBlockSelection.clear()
    }

    // MARK: - Copy / Cut / Delete

    private func copySelectedBlocks() {
        let selected = document.blocks.filter { multiBlockSelection.selectedBlockIDs.contains($0.id) }
        let markdown = selected.map { BlockSerializer.serializeBlock($0) }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func cutSelectedBlocks() {
        copySelectedBlocks()
        deleteSelectedBlocks()
    }

    private func deleteSelectedBlocks() {
        let ids = multiBlockSelection.selectedBlockIDs
        clearMultiBlockSelection()
        if let fallbackIdx = document.removeBlocks(ids: ids) {
            focusedBlockID = document.blocks[fallbackIdx].id
            pendingCursorOffset = 0
        }
    }

    // MARK: - Mouse Drag Across Blocks

    private func installDragMonitor() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [self] event in
            handleMouseDrag(event)
            return event
        }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [self] event in
            if isDraggingAcrossBlocks {
                isDraggingAcrossBlocks = false
                // Make key handler first responder if blocks are selected
                if multiBlockSelection.isActive {
                    DispatchQueue.main.async {
                        if let window = NSApp.keyWindow,
                           let keyView = findKeyHandlerView(in: window.contentView)
                        {
                            window.makeFirstResponder(keyView)
                        }
                    }
                }
            }
            return event
        }
    }

    // MARK: - In-Document Search

    private func installFindMonitor() {
        guard findMonitor == nil else { return }
        findMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "f"
            {
                // Clear block focus so the search bar TextField keeps first responder
                focusedBlockID = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    searchState.isActive = true
                }
                return nil // consume the event
            }
            return event
        }
    }

    // MARK: - Inline Rewrite Shortcut (⌘⇧E)

    /// Begins the inline rewrite flow on the current text selection. Anchors the popover
    /// near the selection toolbar (offset below) so it appears just under the toolbar
    /// position; falls back to the text view's midpoint when no anchor is known.
    private func beginInlineRewrite(textView: MarkdownNSTextView) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let selected = (textView.string as NSString).substring(with: range)
        let anchor: CGPoint = {
            if let pos = selectionToolbarPosition {
                return CGPoint(x: pos.x, y: pos.y + 180)
            }
            return CGPoint(x: textView.bounds.midX, y: textView.bounds.midY)
        }()
        rewriteState.begin(
            textView: textView,
            range: range,
            selectedText: selected,
            anchor: anchor
        )
    }

    /// Intercepts ⌘⇧E and triggers the rewrite flow on the current selection.
    /// Works even when the floating toolbar is hidden (e.g. right after scrolling).
    private func installRewriteShortcutMonitor() {
        guard rewriteShortcutMonitor == nil else { return }
        rewriteShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == cmdShift,
                  event.charactersIgnoringModifiers?.lowercased() == "e"
            else { return event }

            // Only fire if there's actually a selection to rewrite
            guard let textView = activeTextView, textView.selectedRange().length > 0 else {
                return event
            }
            handleFormattingAction(.rewrite)
            return nil // consume
        }
    }

    private func navigateToCurrentMatch(proxy: ScrollViewProxy?) {
        guard let match = searchState.currentMatch else { return }
        focusedBlockID = match.blockID
        focusedItemID = match.itemID
        pendingCursorOffset = match.range.location
        programmaticFocusTarget = match.blockID
    }

    private func removeDragMonitor() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func handleMouseDrag(_ event: NSEvent) {
        guard let window = event.window,
              let contentView = window.contentView
        else { return }

        let windowPoint = event.locationInWindow
        let contentPoint = contentView.convert(windowPoint, from: nil)

        // Find which block the mouse is currently over
        guard let currentBlockID = blockAtPoint(contentPoint) else { return }

        if !isDraggingAcrossBlocks {
            // Check if we've crossed a block boundary
            if let focused = focusedBlockID, focused != currentBlockID {
                // Start multi-block selection
                isDraggingAcrossBlocks = true
                multiBlockSelection.dragOriginBlockID = focused
                multiBlockSelection.anchorBlockID = focused

                // Select range between origin and current
                selectBlockRange(from: focused, to: currentBlockID)
                selectionToolbarPosition = nil
            }
        } else {
            // Continue extending the selection
            if let origin = multiBlockSelection.dragOriginBlockID {
                selectBlockRange(from: origin, to: currentBlockID)
            }
        }
    }

    /// Hit-tests which block is at the given point (in content view coordinates).
    private func blockAtPoint(_ point: CGPoint) -> BlockID? {
        // Convert content view point to scroll coordinate space
        // blockFrames are in the "editorScroll" coordinate space
        // We need to find which block's frame contains the point
        for (blockID, frame) in blockFrames {
            // Use a vertical-only hit test (ignore X since blocks span full width)
            if point.y >= frame.minY, point.y <= frame.maxY {
                return blockID
            }
        }
        return nil
    }

    /// Selects all blocks in the contiguous range between two block IDs.
    private func selectBlockRange(from startID: BlockID, to endID: BlockID) {
        guard let startIdx = document.index(of: startID),
              let endIdx = document.index(of: endID)
        else { return }
        multiBlockSelection.selectRange(from: startIdx, to: endIdx, in: document.blocks)
    }

    /// Finds the KeyHandlerNSView in the view hierarchy.
    private func findKeyHandlerView(in view: NSView?) -> KeyHandlerNSView? {
        guard let view else { return nil }
        if let keyView = view as? KeyHandlerNSView {
            return keyView
        }
        for subview in view.subviews {
            if let found = findKeyHandlerView(in: subview) {
                return found
            }
        }
        return nil
    }
}
