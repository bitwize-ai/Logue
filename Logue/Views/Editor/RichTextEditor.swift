// swiftlint:disable file_length
import AppKit
import SwiftUI

// MARK: - Shared Notification

extension Notification.Name {
    static let logueAskAI = Notification.Name("LogueAskAI")
}

// MARK: - FormattingAction

enum FormattingAction {
    case bold, italic, underline, strikethrough, inlineCode, link, askAI, copySelection, rewrite
}

struct FormattingState {
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStrikethrough = false
}

// MARK: - RichTextEditor

/// NSViewRepresentable wrapping NSTextView with:
///   • Inline suggestion underlines (NSLayoutManager temporary attributes)
///   • Per-line hover + and ⋮⋮ buttons (add block / block options)
///   • Floating selection toolbar (Bold, Italic, Underline, Strikethrough, Ask AI)
///   • Slash command popup (type / to search block types)
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var suggestions: [Suggestion]
    var fontSize: CGFloat
    var onCursorPositionChange: ((Int) -> Void)?
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?
    var onTextViewReady: ((WritingNSTextView) -> Void)?
    var onStaleSuggestionIDs: (([UUID]) -> Void)?

    /// Returns a system font that respects the user's system-level text size preference.
    static func preferredBodyFont(sizeAdjustment: CGFloat = 0) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: .body)
        if sizeAdjustment == 0 {
            return base
        }
        return NSFont.systemFont(ofSize: base.pointSize + sizeAdjustment)
    }

    init(
        text: Binding<String>,
        suggestions: [Suggestion],
        fontSize: CGFloat = 15,
        onCursorPositionChange: ((Int) -> Void)? = nil,
        onSuggestionAccepted: ((Suggestion) -> Void)? = nil,
        onSuggestionDismissed: ((Suggestion) -> Void)? = nil,
        onTextViewReady: ((WritingNSTextView) -> Void)? = nil,
        onStaleSuggestionIDs: (([UUID]) -> Void)? = nil
    ) {
        _text = text
        self.suggestions = suggestions
        self.fontSize = fontSize
        self.onCursorPositionChange = onCursorPositionChange
        self.onSuggestionAccepted = onSuggestionAccepted
        self.onSuggestionDismissed = onSuggestionDismissed
        self.onTextViewReady = onTextViewReady
        self.onStaleSuggestionIDs = onStaleSuggestionIDs
    }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        // Set up custom text system with WritingLayoutManager for bullet/checkbox rendering
        let textStorage = NSTextStorage()
        let layoutManager = WritingLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = WritingNSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        let sizeAdj: CGFloat = fontSize > 15 ? 3 : 0
        textView.font = RichTextEditor.preferredBodyFont(sizeAdjustment: sizeAdj)
        textView.textContainerInset = NSSize(
            width: AppThemeConstants.editorHorizontalInset,
            height: AppThemeConstants.editorVerticalInset
        )
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.backgroundColor = NSColor(AppThemeConstants.contentBackground)
        textView.string = text

        // Enable Find & Replace (Cmd+F / Cmd+Option+F)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let sizedFont = RichTextEditor.preferredBodyFont(sizeAdjustment: sizeAdj)
        textView.defaultFont = sizedFont
        textView.applyDefaultStyling()
        textView.loadTableAttachments()
        textView.scheduleMarkdownRestyling()

        onTextViewReady?(textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.isFindBarVisible = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        guard let textView = scrollView.documentView as? WritingNSTextView else { return }

        // Keep background in sync with theme
        textView.backgroundColor = NSColor(AppThemeConstants.contentBackground)

        // Update font if changed
        let sizeAdj: CGFloat = fontSize > 15 ? 3 : 0
        let expectedFont = RichTextEditor.preferredBodyFont(sizeAdjustment: sizeAdj)
        let fontChanged = textView.defaultFont.pointSize != expectedFont.pointSize
        if fontChanged {
            textView.defaultFont = expectedFont
            textView.font = expectedFont
            textView.applyDefaultStyling()
        }

        // Sync text only when changed externally (avoids caret jumping on each keystroke)
        let serialized = textView.serializeText()
        if serialized != text {
            let sel = textView.selectedRange()
            // Remove existing table overlays before loading new text
            for (_, overlay) in textView.tableOverlays {
                overlay.removeFromSuperview()
            }
            textView.tableOverlays.removeAll()

            textView.string = text
            textView.loadTableAttachments()
            let safeLocation = min(sel.location, textView.string.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            textView.scheduleMarkdownRestyling()
        }

        textView.updateTableOverlayPositions()
        applyUnderlines(to: textView)
        textView.onSuggestionAccepted = onSuggestionAccepted
        textView.onSuggestionDismissed = onSuggestionDismissed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCursorChange: onCursorPositionChange)
    }

    // MARK: - Underline Rendering

    private func applyUnderlines(to textView: WritingNSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let nsString = textView.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)

        var resolved: [(suggestion: Suggestion, range: NSRange)] = []

        for suggestion in suggestions {
            // Search for the original text in the current editor string using word
            // boundaries to avoid matching substrings (e.g., "ad" inside "already").
            let escaped = NSRegularExpression.escapedPattern(for: suggestion.original)
            let pattern = "\\b\(escaped)\\b"
            let range: NSRange
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: textView.string, range: fullRange)
            {
                range = match.range
            } else {
                // Fallback to plain search if regex fails (e.g., original has special chars)
                let found = nsString.range(of: suggestion.original, options: [], range: fullRange)
                guard found.location != NSNotFound else { continue }
                range = found
            }

            layoutManager.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                forCharacterRange: range
            )
            layoutManager.addTemporaryAttribute(
                .underlineColor,
                value: suggestion.type.nsColor,
                forCharacterRange: range
            )
            resolved.append((suggestion: suggestion, range: range))
        }

        textView.resolvedSuggestions = resolved

        // Auto-dismiss stale LLM suggestions whose original text no longer exists in the editor
        let resolvedIDs = Set(resolved.map(\.suggestion.id))
        let staleIDs = suggestions
            .filter { $0.textRange.location == NSNotFound } // LLM suggestions only
            .filter { !resolvedIDs.contains($0.id) }
            .map(\.id)
        if !staleIDs.isEmpty {
            DispatchQueue.main.async { [onStaleSuggestionIDs] in
                onStaleSuggestionIDs?(staleIDs)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCursorChange: ((Int) -> Void)?

        init(text: Binding<String>, onCursorChange: ((Int) -> Void)?) {
            self.text = text
            self.onCursorChange = onCursorChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? WritingNSTextView else { return }
            let serialized = tv.serializeText()
            if text.wrappedValue != serialized {
                text.wrappedValue = serialized
            }
            tv.scheduleMarkdownRestyling()
            tv.updateSlashCommandState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? WritingNSTextView else { return }
            onCursorChange?(tv.selectedRange().location)
            tv.updateSelectionToolbar()
            tv.updateDelimiterVisibility()
        }
    }
}

// MARK: - WritingNSTextView

/// NSTextView subclass that adds:
///   • Comfortable 1.5× line spacing
///   • Per-line hover + and ⋮⋮ buttons (add block / block options)
///   • Floating selection formatting toolbar
///   • Click-to-fix inline suggestion popover
///   • List auto-continuation on Enter
///   • Slash command popup
///   • Checkbox click-to-toggle
final class WritingNSTextView: NSTextView {
    // MARK: - Inline Suggestion State

    /// Suggestions with resolved character ranges — populated by applyUnderlines.
    var resolvedSuggestions: [(suggestion: Suggestion, range: NSRange)] = []
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?

    // MARK: - Markdown Styling

    let markdownStyler = MarkdownStyler()
    var restyleTimer: Timer?

    func scheduleMarkdownRestyling() {
        restyleTimer?.invalidate()
        restyleTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self, let textStorage else { return }
            let savedSelection = selectedRange()
            markdownStyler.restyle(
                textStorage,
                defaultFont: defaultFont,
                defaultParaStyle: defaultParaStyle,
                defaultTextColor: defaultTextColor
            )
            setSelectedRange(savedSelection)
            updateTableOverlayPositions()
        }
    }

    /// Immediately restyle without debounce — used after table mutations to prevent flash.
    func restyleImmediately() {
        restyleTimer?.invalidate()
        guard let textStorage else { return }
        let savedSelection = selectedRange()
        markdownStyler.restyle(
            textStorage,
            defaultFont: defaultFont,
            defaultParaStyle: defaultParaStyle,
            defaultTextColor: defaultTextColor
        )
        setSelectedRange(savedSelection)
        updateTableOverlayPositions()
    }

    func updateDelimiterVisibility() {
        // No-op: delimiters are always hidden in WYSIWYG mode
    }

    // MARK: - Default Styling

    var defaultFont: NSFont = .preferredFont(forTextStyle: .body)

    var defaultParaStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = AppThemeConstants.lineSpacingDefault
        style.paragraphSpacing = AppThemeConstants.bodyParagraphSpacing
        return style
    }()

    var defaultTextColor: NSColor = .labelColor

    func applyDefaultStyling(to range: NSRange? = nil) {
        guard let textStorage else { return }
        let target = range ?? NSRange(location: 0, length: textStorage.length)
        guard target.length > 0 else {
            typingAttributes = [
                .font: defaultFont,
                .foregroundColor: defaultTextColor,
                .paragraphStyle: defaultParaStyle,
            ]
            return
        }
        textStorage.addAttributes([
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ], range: target)
        typingAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ]
    }

    // MARK: - Table Block Overlay Management

    /// Active table overlay views keyed by their TableAttachment UUID.
    var tableOverlays: [UUID: TableBlockView] = [:]

    /// Inserts a table as an NSTextAttachment with an interactive overlay view.
    func insertTableBlock(at charIndex: Int) {
        guard let textStorage else { return }
        let nsString = string as NSString
        let insertAt: Int
        let leadingNewlines: String
        if nsString.length == 0 {
            insertAt = 0
            leadingNewlines = ""
        } else {
            let safeLoc = min(charIndex, nsString.length - 1)
            let lr = nsString.lineRange(for: NSRange(location: safeLoc, length: 0))
            insertAt = min(NSMaxRange(lr), nsString.length)
            let endsWithNewline = insertAt > 0 && nsString.substring(with: NSRange(location: insertAt - 1, length: 1)) == "\n"
            let endsWithBlankLine = insertAt > 1 && nsString.substring(with: NSRange(location: insertAt - 2, length: 2)) == "\n\n"
            if endsWithBlankLine {
                leadingNewlines = ""
            } else if endsWithNewline {
                leadingNewlines = "\n"
            } else {
                leadingNewlines = "\n\n"
            }
        }

        // Compute available width for the table
        let containerWidth = textContainer?.size.width ?? 600
        let availableWidth = containerWidth - textContainerInset.width * 2

        // Create the table data and attachment
        let tableData = TableBlockData(columns: 3, rowCount: 2, availableWidth: availableWidth)
        let attachment = TableAttachment(tableData: tableData)

        // Build the attributed string: leading newlines + attachment + trailing newline
        let result = NSMutableAttributedString()
        if !leadingNewlines.isEmpty {
            result.append(NSAttributedString(string: leadingNewlines, attributes: [
                .font: defaultFont,
                .foregroundColor: defaultTextColor,
                .paragraphStyle: defaultParaStyle,
            ]))
        }
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ]))

        // Insert into text storage
        guard shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: result.string) else { return }
        textStorage.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: result)
        didChangeText()

        // Place cursor after the table
        let cursorPos = insertAt + result.length
        setSelectedRange(NSRange(location: cursorPos, length: 0))

        // Create and position overlay view
        createTableOverlay(for: attachment)
        updateTableOverlayPositions()
    }

    /// Creates a TableBlockView overlay for the given attachment.
    func createTableOverlay(for attachment: TableAttachment) {
        let containerWidth = textContainer?.size.width ?? 600
        let availableWidth = containerWidth - textContainerInset.width * 2

        let overlay = TableBlockView(tableData: attachment.tableData)
        overlay.availableWidth = availableWidth
        overlay.updateSize()
        overlay.onDataChanged = { [weak self] in
            self?.invalidateTableAttachmentLayout(for: attachment)
        }
        addSubview(overlay)
        tableOverlays[attachment.tableID] = overlay
    }

    /// Repositions all table overlay views to match their attachment rects.
    func updateTableOverlayPositions() {
        guard let textStorage, let layoutManager, let textContainer else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let containerWidth = textContainer.size.width
        let availableWidth = containerWidth - textContainerInset.width * 2

        // Re-autosize table columns and invalidate layout so the attachment
        // cell frame is recomputed with the current container width.
        var idx = fullRange.location
        while idx < NSMaxRange(fullRange) {
            var effectiveRange = NSRange()
            if let att = textStorage.attribute(.attachment, at: idx, effectiveRange: &effectiveRange) as? TableAttachment {
                let overlay = tableOverlays[att.tableID]
                if overlay == nil || overlay?.availableWidth != availableWidth {
                    att.tableData.autoSizeColumns(availableWidth: availableWidth)
                    layoutManager.invalidateLayout(forCharacterRange: effectiveRange, actualCharacterRange: nil)
                }
                idx = NSMaxRange(effectiveRange)
            } else {
                idx += 1
            }
        }

        // Force layout computation so glyph positions are up-to-date.
        layoutManager.ensureLayout(forCharacterRange: fullRange)

        var foundIDs = Set<UUID>()

        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let tableAttachment = value as? TableAttachment else { return }
            foundIDs.insert(tableAttachment.tableID)

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let origin = NSPoint(
                x: rect.origin.x + self.textContainerOrigin.x,
                y: rect.origin.y + self.textContainerOrigin.y
            )

            if let overlay = self.tableOverlays[tableAttachment.tableID] {
                overlay.availableWidth = availableWidth
                overlay.updateSize()
                overlay.frame = NSRect(origin: origin, size: tableAttachment.tableData.fullSize)
            } else {
                self.createTableOverlay(for: tableAttachment)
                if let overlay = self.tableOverlays[tableAttachment.tableID] {
                    overlay.frame = NSRect(origin: origin, size: tableAttachment.tableData.fullSize)
                }
            }
        }

        // Remove stale overlays for deleted attachments
        for (id, overlay) in tableOverlays where !foundIDs.contains(id) {
            overlay.removeFromSuperview()
            tableOverlays.removeValue(forKey: id)
        }
    }

    /// Relayouts the attachment cell size and repositions the overlay after table data changes.
    func invalidateTableAttachmentLayout(for attachment: TableAttachment) {
        guard let textStorage, let layoutManager else { return }
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            guard let ta = value as? TableAttachment, ta.tableID == attachment.tableID else { return }
            // Invalidate layout for the attachment character to recompute cell frame
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            stop.pointee = true
        }
        updateTableOverlayPositions()

        // Sync updated table content back to the text binding so it persists across tab switches.
        let serialized = serializeText()
        if let delegate = delegate as? RichTextEditor.Coordinator {
            if delegate.text.wrappedValue != serialized {
                delegate.text.wrappedValue = serialized
            }
        }
    }

    /// Returns the text with table attachments serialized back to markdown.
    func serializeText() -> String {
        guard let textStorage, textStorage.length > 0 else { return string }

        var result = ""
        var lastEnd = 0
        let nsString = textStorage.string as NSString

        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let tableAttachment = value as? TableAttachment else { return }
            // Append text before this attachment
            if range.location > lastEnd {
                result += nsString.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
            }
            // Append table as markdown
            result += tableAttachment.tableData.toMarkdown()
            lastEnd = NSMaxRange(range)
        }

        // Append remaining text after last attachment
        if lastEnd < nsString.length {
            result += nsString.substring(with: NSRange(location: lastEnd, length: nsString.length - lastEnd))
        }

        return result
    }

    /// Finds markdown table blocks in lines (consecutive lines starting/ending with |).
    private static func findTableBlocks(in lines: [String]) -> [(startLine: Int, endLine: Int)] {
        var blocks: [(startLine: Int, endLine: Int)] = []
        var idx = 0
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|"), line.hasSuffix("|"), idx + 1 < lines.count {
                let nextLine = lines[idx + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.contains("---"), nextLine.hasPrefix("|") {
                    var endLine = idx + 1
                    for j in (idx + 2) ..< lines.count {
                        let bodyLine = lines[j].trimmingCharacters(in: .whitespaces)
                        if bodyLine.hasPrefix("|"), bodyLine.hasSuffix("|") {
                            endLine = j
                        } else {
                            break
                        }
                    }
                    blocks.append((idx, endLine))
                    idx = endLine + 1
                    continue
                }
            }
            idx += 1
        }
        return blocks
    }

    /// Converts markdown tables in the text storage to overlay table attachments.
    func loadTableAttachments() {
        guard let textStorage, textStorage.length > 0 else { return }
        let lines = textStorage.string.components(separatedBy: "\n")
        let tableBlocks = Self.findTableBlocks(in: lines)
        guard !tableBlocks.isEmpty else { return }

        let containerWidth = textContainer?.size.width ?? 600
        let availableWidth = containerWidth - textContainerInset.width * 2

        for block in tableBlocks.reversed() {
            var charStart = 0
            for lineIdx in 0 ..< block.startLine {
                charStart += lines[lineIdx].utf16.count + 1
            }
            var charEnd = charStart
            for lineIdx in block.startLine ... block.endLine {
                charEnd += lines[lineIdx].utf16.count + (lineIdx < block.endLine ? 1 : 0)
            }
            let tableRange = NSRange(location: charStart, length: charEnd - charStart)

            var cellRows: [[String]] = []
            for lineIdx in block.startLine ... block.endLine {
                if lineIdx == block.startLine + 1 {
                    continue
                }
                let cells = lines[lineIdx].split(separator: "|", omittingEmptySubsequences: false)
                    .map(String.init).dropFirst().dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                cellRows.append(Array(cells))
            }

            guard let colCount = cellRows.first?.count, colCount > 0 else { continue }

            let tableData = TableBlockData(columns: colCount, rowCount: cellRows.count, availableWidth: availableWidth)
            tableData.rows = cellRows.map { row in
                var paddedRow = row
                while paddedRow.count < colCount {
                    paddedRow.append("")
                }
                return Array(paddedRow.prefix(colCount))
            }
            tableData.autoSizeColumns(availableWidth: availableWidth)

            let attachment = TableAttachment(tableData: tableData)
            textStorage.replaceCharacters(in: tableRange, with: NSAttributedString(attachment: attachment))
            createTableOverlay(for: attachment)
        }
    }

    // MARK: - Block Buttons (+ and ⋮⋮)

    let addBlockButton: NSButton = {
        let btn = NSButton()
        let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        btn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add block")?
            .withSymbolConfiguration(symConfig)
        btn.image?.isTemplate = true
        btn.imageScaling = .scaleNone
        btn.bezelStyle = .recessed
        btn.isBordered = true
        btn.contentTintColor = .tertiaryLabelColor
        btn.isHidden = true
        return btn
    }()

    let blockOptionsButton: NSButton = {
        let btn = NSButton()
        // Use a six-dot grip icon (⋮⋮)
        btn.title = "⋮⋮"
        btn.font = .systemFont(ofSize: 13, weight: .bold)
        btn.imageScaling = .scaleNone
        btn.bezelStyle = .recessed
        btn.isBordered = true
        btn.contentTintColor = .tertiaryLabelColor
        btn.isHidden = true
        return btn
    }()

    var hoveredCharIndex: Int = 0

    // MARK: - Selection Toolbar

    private var selectionPanel: NSPanel?
    private var toolbarTargetRange: NSRange = .init(location: 0, length: 0)

    // MARK: - Slash Command State

    var slashCommandPanel: NSPanel?
    /// Character index of the `/` that triggered the slash command.
    var slashTriggerIndex: Int?

    // MARK: - Setup

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupBlockButtons()
        setupWindowObservers()
    }

    private func setupBlockButtons() {
        addBlockButton.target = self
        addBlockButton.action = #selector(showAddBlockMenu)
        addSubview(addBlockButton)

        blockOptionsButton.target = self
        blockOptionsButton.action = #selector(showBlockOptionsMenu)
        addSubview(blockOptionsButton)
    }

    private func setupWindowObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowResigned),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    @objc
    private func handleWindowResigned() {
        addBlockButton.isHidden = true
        blockOptionsButton.isHidden = true
        hideSelectionToolbar()
        hideSlashCommandPanel()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        hideSelectionToolbar()
        hideSlashCommandPanel()
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateBlockButtons(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        addBlockButton.isHidden = true
        blockOptionsButton.isHidden = true
    }

    private func updateBlockButtons(at point: NSPoint) {
        guard let layoutManager,
              let textContainer,
              !string.isEmpty
        else {
            addBlockButton.isHidden = true
            blockOptionsButton.isHidden = true
            return
        }

        let adj = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let clamped = NSPoint(
            x: max(0, min(adj.x, textContainer.size.width)),
            y: max(0, adj.y)
        )

        var partial = CGFloat(0)
        let glyphIdx = layoutManager.glyphIndex(
            for: clamped,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &partial
        )
        guard glyphIdx < layoutManager.numberOfGlyphs else {
            addBlockButton.isHidden = true
            blockOptionsButton.isHidden = true
            return
        }

        hoveredCharIndex = layoutManager.characterIndexForGlyph(at: glyphIdx)

        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
        lineRect.origin.x += textContainerOrigin.x
        lineRect.origin.y += textContainerOrigin.y

        positionBlockButtons(in: lineRect)
    }

    private func positionBlockButtons(in lineRect: NSRect) {
        let btnSize: CGFloat = 22
        let gap: CGFloat = 2
        let optionsX = max(2, textContainerInset.width - btnSize - 6)
        let addX = optionsX - btnSize - gap

        addBlockButton.frame = NSRect(x: addX, y: lineRect.midY - btnSize / 2, width: btnSize, height: btnSize)
        blockOptionsButton.frame = NSRect(x: optionsX, y: lineRect.midY - btnSize / 2, width: btnSize, height: btnSize)
        addBlockButton.isHidden = false
        blockOptionsButton.isHidden = false
    }
}

// MARK: - Selection Toolbar

extension WritingNSTextView {
    func updateSelectionToolbar() {
        let sel = selectedRange()
        if sel.length > 0 {
            toolbarTargetRange = sel
            showSelectionToolbar(for: sel)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.selectionToolbarHideInterval) { [weak self] in
                guard let self else { return }
                if selectedRange().length == 0 {
                    hideSelectionToolbar()
                }
            }
        }
    }

    private func showSelectionToolbar(for range: NSRange) {
        guard let layoutManager,
              let textContainer,
              let window
        else {
            hideSelectionToolbar()
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let windowRect = convert(rect, to: nil)
        let screenRect = window.convertToScreen(windowRect)

        if selectionPanel == nil {
            createSelectionPanel()
        }
        guard let panel = selectionPanel else { return }

        let pSize = panel.frame.size
        let pWidth = max(pSize.width, 260)
        let pHeight = pSize.height
        var x = screenRect.midX - pWidth / 2
        let y = screenRect.maxY + 8

        if let screen = window.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            x = max(frame.minX + 8, min(x, frame.maxX - pWidth - 8))
        }

        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.setFrame(NSRect(x: x, y: y, width: pWidth, height: pHeight), display: false)
        panel.orderFront(nil)
        updateSelectionToolbarState()
    }

    private func updateSelectionToolbarState() {
        guard let panel = selectionPanel,
              let hostingView = panel.contentView as? NSHostingView<SelectionToolbarView>
        else { return }
        let state = currentFormattingState()
        hostingView.rootView = SelectionToolbarView(formattingState: state) { [weak self] action in
            self?.applyFormattingAction(action)
        }
    }

    private func createSelectionPanel() {
        let state = currentFormattingState()
        let toolbarView = SelectionToolbarView(formattingState: state) { [weak self] action in
            self?.applyFormattingAction(action)
        }
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let ideal = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: ideal),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        selectionPanel = panel
    }

    func hideSelectionToolbar() {
        if let panel = selectionPanel, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        selectionPanel?.orderOut(nil)
    }
}

// MARK: - Formatting Actions

extension WritingNSTextView {
    func currentFormattingState() -> FormattingState {
        guard let textStorage, textStorage.length > 0 else { return FormattingState() }
        let sel = selectedRange()
        let queryIndex = max(0, min(sel.location > 0 ? sel.location - 1 : 0, textStorage.length - 1))
        var state = FormattingState()
        if let font = textStorage.attribute(.font, at: queryIndex, effectiveRange: nil) as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            state.isBold = traits.contains(.bold)
            state.isItalic = traits.contains(.italic)
        }
        if let underline = textStorage.attribute(.underlineStyle, at: queryIndex, effectiveRange: nil) as? Int {
            state.isUnderlined = underline != 0
        }
        if let strike = textStorage.attribute(.strikethroughStyle, at: queryIndex, effectiveRange: nil) as? Int {
            state.isStrikethrough = strike != 0
        }
        return state
    }

    func applyFormattingAction(_ action: FormattingAction) {
        let sel = toolbarTargetRange.length > 0 ? toolbarTargetRange : selectedRange()

        switch action {
        case .bold:
            wrapSelectionWithMarkdown(sel, prefix: "**", suffix: "**")

        case .italic:
            wrapSelectionWithMarkdown(sel, prefix: "*", suffix: "*")

        case .underline:
            guard sel.length > 0 else { break }
            let current = textStorage?.attribute(.underlineStyle, at: sel.location, effectiveRange: nil) as? Int
            let value = (current ?? 0) != 0 ? 0 : NSUnderlineStyle.single.rawValue
            textStorage?.addAttribute(.underlineStyle, value: value, range: sel)

        case .strikethrough:
            wrapSelectionWithMarkdown(sel, prefix: "~~", suffix: "~~")

        case .inlineCode:
            wrapSelectionWithMarkdown(sel, prefix: "`", suffix: "`")

        case .link:
            guard sel.length > 0 else { break }
            let selectedText = (string as NSString).substring(with: sel)
            let linked = "[\(selectedText)](url)"
            guard shouldChangeText(in: sel, replacementString: linked) else { break }
            replaceCharacters(in: sel, with: linked)
            didChangeText()
            // Select "url" so user can type the actual URL
            let urlStart = sel.location + selectedText.utf16.count + 2 // past ](
            setSelectedRange(NSRange(location: urlStart, length: 3))

        case .askAI:
            guard sel.length > 0 else { break }
            let selectedText = (string as NSString).substring(with: sel)
            NotificationCenter.default.post(name: .logueAskAI, object: selectedText)

        case .copySelection:
            guard sel.length > 0 else { break }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString((string as NSString).substring(with: sel), forType: .string)

        case .rewrite:
            // Inline rewrite is a BlockEditor-only feature; in the legacy RichTextEditor
            // we fall back to opening the chat with the selection.
            guard sel.length > 0 else { break }
            let selectedText = (string as NSString).substring(with: sel)
            NotificationCenter.default.post(name: .logueAskAI, object: selectedText)
        }

        hideSelectionToolbar()
    }

    private func wrapSelectionWithMarkdown(_ sel: NSRange, prefix: String, suffix: String) {
        guard sel.length > 0 else { return }
        let nsString = string as NSString
        let selectedText = nsString.substring(with: sel)

        if selectedText.hasPrefix(prefix), selectedText.hasSuffix(suffix),
           selectedText.count >= prefix.count + suffix.count
        {
            let unwrapped = String(selectedText.dropFirst(prefix.count).dropLast(suffix.count))
            guard shouldChangeText(in: sel, replacementString: unwrapped) else { return }
            replaceCharacters(in: sel, with: unwrapped)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location, length: unwrapped.utf16.count))
        } else {
            let wrapped = prefix + selectedText + suffix
            guard shouldChangeText(in: sel, replacementString: wrapped) else { return }
            replaceCharacters(in: sel, with: wrapped)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + prefix.utf16.count, length: selectedText.utf16.count))
        }
    }
}

// MARK: - Inline Suggestion Click & Checkbox Toggle

extension WritingNSTextView {
    /// Converts a view-space point to a character index using the layout manager.
    private func charIndex(at viewPoint: NSPoint) -> Int {
        guard let layoutManager, let textContainer, !string.isEmpty else { return 0 }
        let adj = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let glyphIdx = layoutManager.glyphIndex(
            for: adj, in: textContainer, fractionOfDistanceThroughGlyph: &fraction
        )
        return layoutManager.characterIndexForGlyph(at: glyphIdx)
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let charIdx = charIndex(at: pt)

        // Check for Cmd+click on links
        if handleLinkClick(at: charIdx, event: event) {
            return
        }

        // Check for checkbox toggle (click on `- [ ]` or `- [x]`)
        if toggleCheckboxIfNeeded(at: charIdx) {
            return
        }

        // Check for suggestion underline click
        if let hit = resolvedSuggestions.first(where: { NSLocationInRange(charIdx, $0.range) }) {
            showSuggestionPopover(for: hit.suggestion, range: hit.range)
            return
        }
        super.mouseDown(with: event)
    }

    /// Returns true if a checkbox was found and toggled at the click position.
    /// Only triggers when clicking within the checkbox prefix area (first 6 chars).
    /// Restores cursor position so the raw markdown doesn't get revealed.
    private func toggleCheckboxIfNeeded(at charIdx: Int) -> Bool {
        let nsString = string as NSString
        guard nsString.length > 0 else { return false }

        let safe = min(max(0, charIdx), nsString.length - 1)
        let lr = nsString.lineRange(for: NSRange(location: safe, length: 0))
        let lineText = nsString.substring(with: lr)

        // Only toggle when clicking on the checkbox marker area
        let clickOffset = safe - lr.location
        guard clickOffset < 6 else { return false }

        // Save cursor position to restore after toggle (prevents revealing raw syntax)
        let savedSelection = selectedRange()

        if lineText.hasPrefix("- [ ] ") {
            let checkboxRange = NSRange(location: lr.location, length: 6)
            replaceRange(checkboxRange, with: "- [x] ")
            setSelectedRange(savedSelection)
            return true
        } else if lineText.hasPrefix("- [x] ") {
            let checkboxRange = NSRange(location: lr.location, length: 6)
            replaceRange(checkboxRange, with: "- [ ] ")
            setSelectedRange(savedSelection)
            return true
        }
        return false
    }

    private func showSuggestionPopover(for suggestion: Suggestion, range: NSRange) {
        guard let layoutManager,
              let textContainer
        else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

        // Use per-glyph positioning for precision: get the line fragment then
        // the exact glyph location within it, rather than boundingRect which
        // can be slightly imprecise with hidden/collapsed markdown delimiters.
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let glyphLocation = layoutManager.location(forGlyphAt: glyphRange.location)

        // Get width from the bounding rect (reliable for width calculation)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        var rect = NSRect(
            x: lineRect.origin.x + glyphLocation.x + textContainerOrigin.x,
            y: lineRect.origin.y + textContainerOrigin.y,
            width: boundingRect.width,
            height: lineRect.height
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let popoverView = InlineSuggestionPopoverView(
            suggestion: suggestion,
            onAccept: { [weak self, weak popover] in
                guard let self else { return }
                insertText(suggestion.replacement, replacementRange: range)
                onSuggestionAccepted?(suggestion)
                popover?.close()
            },
            onDismiss: { [weak self, weak popover] in
                self?.onSuggestionDismissed?(suggestion)
                popover?.close()
            }
        )
        popover.contentViewController = NSHostingController(rootView: popoverView)
        popover.show(relativeTo: rect, of: self, preferredEdge: .minY)
    }
}

// MARK: - Link Insertion & Click

extension WritingNSTextView {
    /// Inserts a markdown link around the selection or at cursor.
    func insertLink() {
        let sel = selectedRange()
        if sel.length > 0 {
            let selectedText = (string as NSString).substring(with: sel)
            // Check if selection looks like a URL
            if selectedText.hasPrefix("http://") || selectedText.hasPrefix("https://") {
                let wrapped = "[link](\(selectedText))"
                guard shouldChangeText(in: sel, replacementString: wrapped) else { return }
                replaceCharacters(in: sel, with: wrapped)
                didChangeText()
                // Select "link" for easy replacement
                setSelectedRange(NSRange(location: sel.location + 1, length: 4))
            } else {
                let wrapped = "[\(selectedText)](url)"
                guard shouldChangeText(in: sel, replacementString: wrapped) else { return }
                replaceCharacters(in: sel, with: wrapped)
                didChangeText()
                // Select "url" for easy replacement
                let urlStart = sel.location + selectedText.utf16.count + 3
                setSelectedRange(NSRange(location: urlStart, length: 3))
            }
        } else {
            let linkTemplate = "[text](url)"
            guard shouldChangeText(in: sel, replacementString: linkTemplate) else { return }
            replaceCharacters(in: sel, with: linkTemplate)
            didChangeText()
            // Select "text" for easy replacement
            setSelectedRange(NSRange(location: sel.location + 1, length: 4))
        }
    }

    /// Opens a markdown link URL when Cmd+clicking on a link.
    func handleLinkClick(at charIdx: Int, event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let nsString = string as NSString
        guard charIdx < nsString.length else { return false }

        // Check if cursor is inside a markdown link
        let lineRange = nsString.lineRange(for: NSRange(location: charIdx, length: 0))
        let lineText = nsString.substring(with: lineRange)

        // Find all [text](url) patterns in the line
        let linkPattern = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
        let lineNS = lineText as NSString
        let matches = linkPattern?.matches(in: lineText, range: NSRange(location: 0, length: lineNS.length)) ?? []

        let charInLine = charIdx - lineRange.location
        for match in matches {
            if charInLine >= match.range.location, charInLine < NSMaxRange(match.range) {
                let urlRange = match.range(at: 2)
                // S-N6: Validate URL scheme before opening
                let urlString = lineNS.substring(with: urlRange)
                if let url = URL(string: urlString),
                   url.scheme == "https" || url.scheme == "http"
                {
                    NSWorkspace.shared.open(url)
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Paste & Key Events

extension WritingNSTextView {
    override func paste(_ sender: Any?) {
        guard let plainText = NSPasteboard.general.string(forType: .string), !plainText.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ]
        let attrString = NSAttributedString(string: plainText, attributes: attrs)
        let sel = selectedRange()
        guard shouldChangeText(in: sel, replacementString: plainText) else { return }
        textStorage?.replaceCharacters(in: sel, with: attrString)
        didChangeText()
        let newLocation = sel.location + plainText.utf16.count
        setSelectedRange(NSRange(location: newLocation, length: 0))
        typingAttributes = attrs
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        switch chars.lowercased() {
        case "b":
            applyFormattingAction(.bold)
            return true
        case "i":
            applyFormattingAction(.italic)
            return true
        case "u":
            applyFormattingAction(.underline)
            return true
        case "x" where event.modifierFlags.contains(.shift):
            applyFormattingAction(.strikethrough)
            return true
        case "k":
            insertLink()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            if slashCommandPanel?.isVisible == true {
                hideSlashCommandPanel()
                return
            }
            hideSelectionToolbar()
        }
        super.keyDown(with: event)
    }
}

// swiftlint:enable file_length
