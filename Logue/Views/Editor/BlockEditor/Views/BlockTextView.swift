// swiftlint:disable file_length
import AppKit
import SwiftUI

// MARK: - BlockTextView

/// A lightweight NSTextView wrapper for editing a single block's text content.
/// When `markdownStyleEnabled` is true, uses MarkdownStyler for WYSIWYG rich text rendering
/// with hidden markdown delimiters (revealed only on the active cursor line).
struct BlockTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .preferredFont(forTextStyle: .body)
    var textColor: NSColor = .labelColor
    var lineSpacing: CGFloat = AppThemeConstants.lineSpacingDefault
    var isFocused: Bool = false
    var placeholder: String = ""
    /// Enable WYSIWYG markdown rendering (bold, italic, code, links with hidden delimiters).
    /// Set to false for code blocks where raw text should be displayed.
    var markdownStyleEnabled: Bool = true
    /// Auto-capitalize the first letter when the user starts typing in an empty block.
    /// Defaults to true; set to false for code blocks.
    var autoCapitalize: Bool = true
    /// Search highlight ranges within this block's text. First element is the range,
    /// second is whether it's the currently active match.
    var searchHighlights: [(range: NSRange, isCurrent: Bool)] = []
    /// When this block is a heading, the level (1-6). Exposed to AX as `AXHeading` role so
    /// VoiceOver's rotor-by-heading navigation finds it. Paragraph/other blocks leave this nil.
    var headingLevel: Int?

    // Callbacks for keyboard events that cross block boundaries
    var onEnter: ((_ cursorOffset: Int) -> Void)?
    var onBackspaceAtStart: (() -> Void)?
    var onArrowUp: ((_ cursorXPosition: CGFloat) -> Void)?
    var onArrowDown: ((_ cursorXPosition: CGFloat) -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onSlashAtStart: (() -> Void)?
    var onDeleteForwardAtEnd: (() -> Void)?
    var onTextChange: ((_ newText: String) -> Void)?
    var onFocusGained: (() -> Void)?
    var onMultiBlockPaste: ((_ markdown: String) -> Void)?
    var onSelectAllBlocks: (() -> Void)?
    var onShiftArrowUpAtTop: (() -> Void)?
    var onShiftArrowDownAtBottom: (() -> Void)?
    var suggestions: [Suggestion] = []
    /// When set, the text view selects the original text of the matching suggestion to highlight it.
    var highlightedSuggestionID: UUID?
    /// Called after the suggestion highlight has been consumed so the parent can clear it.
    var onHighlightedSuggestionConsumed: (() -> Void)?
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?
    var pendingCursorOffset: Binding<Int?>?
    var pendingCursorXPosition: Binding<CGFloat?>?
    var goalColumnX: Binding<CGFloat?>?
    var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?

    func makeNSView(context: Context) -> BlockNSTextView {
        let textView = BlockNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = markdownStyleEnabled
        textView.allowsUndo = true
        textView.isEditable = isFocused
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindPanel = false
        textView.font = font
        textView.typingAttributes = makeTypingAttributes()
        textView.markdownStyleEnabled = markdownStyleEnabled
        textView.autoCapitalize = autoCapitalize
        textView.baseFont = font
        textView.baseTextColor = textColor
        textView.baseLineSpacing = lineSpacing
        textView.headingLevel = headingLevel

        // Set initial text
        textView.string = text

        // Apply initial markdown styling
        if markdownStyleEnabled, let ts = textView.textStorage {
            textView.markdownStyler.restyleInline(ts, defaultFont: font, defaultParaStyle: makeParaStyle(), defaultTextColor: textColor)
        }

        // Store callbacks
        textView.onEnter = onEnter
        textView.onBackspaceAtStart = onBackspaceAtStart
        textView.onArrowUp = onArrowUp
        textView.onArrowDown = onArrowDown
        textView.onTab = onTab
        textView.onBackTab = onBackTab
        textView.onSlashAtStart = onSlashAtStart
        textView.onDeleteForwardAtEnd = onDeleteForwardAtEnd
        textView.onFocusGained = onFocusGained
        textView.onMultiBlockPaste = onMultiBlockPaste
        textView.onSelectAllBlocks = onSelectAllBlocks
        textView.onShiftArrowUpAtTop = onShiftArrowUpAtTop
        textView.onShiftArrowDownAtBottom = onShiftArrowDownAtBottom
        textView.goalColumnXBinding = goalColumnX

        return textView
    }

    func updateNSView(_ textView: BlockNSTextView, context: Context) {
        // Update editable state based on focus
        textView.isEditable = isFocused

        // Force restyle on focus transition to prevent delimiter flash
        if isFocused, !context.coordinator.wasFocused {
            if markdownStyleEnabled, let ts = textView.textStorage {
                textView.markdownStyler.invalidate()
                textView.markdownStyler.restyleInline(
                    ts, defaultFont: font,
                    defaultParaStyle: makeParaStyle(),
                    defaultTextColor: textColor
                )
            }
        }
        context.coordinator.wasFocused = isFocused

        // Update auto-capitalize flag
        textView.autoCapitalize = autoCapitalize

        // Keep heading-level in sync so turning a paragraph into a heading (or vice versa)
        // updates the AX role + subrole without needing to recreate the text view.
        if textView.headingLevel != headingLevel {
            textView.headingLevel = headingLevel
        }

        // Update callbacks
        updateCallbacks(on: textView, coordinator: context.coordinator)

        // Update text if it changed externally (not from user typing)
        if textView.string != text, !context.coordinator.isEditing {
            textView.string = text
            // Re-apply markdown styling for externally changed text
            if markdownStyleEnabled, let ts = textView.textStorage {
                textView.markdownStyler.invalidate()
                textView.markdownStyler.restyleInline(ts, defaultFont: font, defaultParaStyle: makeParaStyle(), defaultTextColor: textColor)
            }
            // Force underline reapplication since replacing text clears temporary attributes
            textView.lastAppliedSuggestionIDs = []
            // Notify SwiftUI that view height may have changed
            textView.invalidateIntrinsicContentSize()
        }

        // Update font if changed
        if textView.baseFont != font {
            textView.font = font
            textView.baseFont = font
            textView.typingAttributes = makeTypingAttributes()
            // Re-restyle with new font
            if markdownStyleEnabled, let ts = textView.textStorage {
                textView.markdownStyler.invalidate()
                textView.markdownStyler.restyleInline(ts, defaultFont: font, defaultParaStyle: makeParaStyle(), defaultTextColor: textColor)
            }
            // Notify SwiftUI that view height changed with new font size
            textView.invalidateIntrinsicContentSize()
        }

        // Keep base line spacing in sync (changes with fontSize)
        if textView.baseLineSpacing != lineSpacing {
            textView.baseLineSpacing = lineSpacing
        }

        // Apply suggestion underlines only when they actually changed
        let currentSuggestions = suggestions
        let newIDs = Set(currentSuggestions.map(\.id))
        if textView.lastAppliedSuggestionIDs != newIDs {
            textView.lastAppliedSuggestionIDs = newIDs
            applySuggestionUnderlines(to: textView, with: currentSuggestions)
        }

        // Apply search highlights
        applySearchHighlights(to: textView, highlights: searchHighlights)

        // Store suggestion callbacks on the text view for click handling
        textView.suggestions = suggestions
        textView.onSuggestionAccepted = onSuggestionAccepted
        textView.onSuggestionDismissed = onSuggestionDismissed

        // Handle focus
        if isFocused, textView.window?.firstResponder !== textView {
            applyFocus(to: textView)
        }

        applyHighlightedSuggestion(to: textView)
    }

    /// Selects the original text of a highlighted suggestion when requested from the panel.
    private func applyHighlightedSuggestion(to textView: BlockNSTextView) {
        guard let targetID = highlightedSuggestionID,
              let suggestion = suggestions.first(where: { $0.id == targetID }),
              !suggestion.original.isEmpty
        else { return }
        let nsString = textView.string as NSString
        // Case-insensitive search — LLM may return different casing than the document
        var range = nsString.range(of: suggestion.original, options: .caseInsensitive)
        // If not found, try stripping markdown delimiters and mapping range back to original
        if range.location == NSNotFound {
            let (stripped, indexMap) = textView.string.markdownStrippedIndexMap()
            let strippedRange = (stripped as NSString).range(of: suggestion.original, options: .caseInsensitive)
            if strippedRange.location != NSNotFound,
               strippedRange.length > 0,
               strippedRange.location < indexMap.count
            {
                let endIdx = min(strippedRange.location + strippedRange.length - 1, indexMap.count - 1)
                if endIdx >= strippedRange.location {
                    let startInOriginal = indexMap[strippedRange.location]
                    let endInOriginal = indexMap[endIdx] + 1
                    range = NSRange(location: startInOriginal, length: endInOriginal - startInOriginal)
                }
            }
        }
        if range.location != NSNotFound {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
        // Always clear so the ID doesn't stay set permanently causing repeated scanning
        DispatchQueue.main.async { [onHighlightedSuggestionConsumed] in
            onHighlightedSuggestionConsumed?()
        }
    }

    private func updateCallbacks(on textView: BlockNSTextView, coordinator: Coordinator) {
        textView.onEnter = onEnter
        textView.onBackspaceAtStart = onBackspaceAtStart
        textView.onArrowUp = onArrowUp
        textView.onArrowDown = onArrowDown
        textView.onTab = onTab
        textView.onBackTab = onBackTab
        textView.onSlashAtStart = onSlashAtStart
        textView.onDeleteForwardAtEnd = onDeleteForwardAtEnd
        textView.onFocusGained = onFocusGained
        textView.onMultiBlockPaste = onMultiBlockPaste
        textView.onSelectAllBlocks = onSelectAllBlocks
        textView.onShiftArrowUpAtTop = onShiftArrowUpAtTop
        textView.onShiftArrowDownAtBottom = onShiftArrowDownAtBottom
        textView.goalColumnXBinding = goalColumnX
        coordinator.onSelectionChange = onSelectionChange
    }

    private func applyFocus(to textView: BlockNSTextView) {
        // If focus was gained via mouse click, NSTextView already positioned the cursor correctly
        if textView.focusedViaClick {
            textView.focusedViaClick = false
            pendingCursorOffset?.wrappedValue = nil
            pendingCursorXPosition?.wrappedValue = nil
            return
        }
        let pendingOffset = pendingCursorOffset?.wrappedValue
        let pendingXPos = pendingCursorXPosition?.wrappedValue
        let goalX = goalColumnX?.wrappedValue
        let pendingBinding = pendingCursorOffset
        let pendingXBinding = pendingCursorXPosition
        let placeCursor = { (tv: BlockNSTextView) in
            tv.window?.makeFirstResponder(tv)
            if let xPos = goalX ?? pendingXPos, let offset = pendingOffset {
                // Arrow key navigation: find the character closest to the desired X position
                let targetLine = targetLineForOffset(offset, in: tv)
                let bestOffset = closestCharacterOffset(toX: xPos, inLineRange: targetLine, textView: tv)
                tv.setSelectedRange(NSRange(location: bestOffset, length: 0))
                pendingXBinding?.wrappedValue = nil
                pendingBinding?.wrappedValue = nil
            } else if let offset = pendingOffset {
                let clamped = min(offset, tv.string.count)
                tv.setSelectedRange(NSRange(location: clamped, length: 0))
                pendingBinding?.wrappedValue = nil
            } else {
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
            }
        }
        if textView.window != nil {
            placeCursor(textView)
        } else {
            DispatchQueue.main.async { placeCursor(textView) }
        }
    }

    /// Returns the line fragment range containing the given character offset.
    private func targetLineForOffset(_ offset: Int, in textView: BlockNSTextView) -> NSRange {
        guard let layoutManager = textView.layoutManager, textView.textContainer != nil else {
            return NSRange(location: offset, length: 0)
        }
        let nsLength = (textView.string as NSString).length
        guard nsLength > 0 else { return NSRange(location: 0, length: 0) }
        let clampedOffset = min(offset, max(0, nsLength - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedOffset)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
        return layoutManager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
    }

    /// Finds the character offset within a line range whose X position is closest to the target.
    private func closestCharacterOffset(toX targetX: CGFloat, inLineRange lineRange: NSRange, textView: BlockNSTextView) -> Int {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return lineRange.location
        }
        let containerOriginX = textView.textContainerOrigin.x
        var bestOffset = lineRange.location
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        let end = NSMaxRange(lineRange)
        for charOffset in lineRange.location ... end {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charOffset, max(0, (textView.string as NSString).length - 1)))
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            let x = rect.origin.x + containerOriginX
            let distance = abs(x - targetX)
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = charOffset
            }
        }
        return min(bestOffset, (textView.string as NSString).length)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, onSelectionChange: onSelectionChange)
    }

    private func applySuggestionUnderlines(to textView: BlockNSTextView, with suggestions: [Suggestion]) {
        guard let layoutManager = textView.layoutManager else { return }
        let nsString = textView.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        // Clear existing underlines
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)

        // Track underlined ranges to disambiguate duplicate text
        var usedRanges: [NSRange] = []

        for suggestion in suggestions {
            // Find the next un-used occurrence of this suggestion's original text
            var searchStart = 0
            var bestRange = NSRange(location: NSNotFound, length: 0)
            while searchStart < nsString.length {
                let searchRange = NSRange(location: searchStart, length: nsString.length - searchStart)
                let found = nsString.range(of: suggestion.original, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }

                // Skip if this range is already used by another suggestion
                let alreadyUsed = usedRanges.contains { $0.location == found.location && $0.length == found.length }
                if !alreadyUsed {
                    bestRange = found
                    break
                }
                searchStart = found.location + 1
            }

            guard bestRange.location != NSNotFound else { continue }
            usedRanges.append(bestRange)

            let color = suggestion.type.nsCategoryColor
            layoutManager.addTemporaryAttribute(.underlineColor, value: color, forCharacterRange: bestRange)
            layoutManager.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.thick.rawValue,
                forCharacterRange: bestRange
            )
        }
    }

    private func applySearchHighlights(to textView: BlockNSTextView, highlights: [(range: NSRange, isCurrent: Bool)]) {
        guard let layoutManager = textView.layoutManager else { return }
        let nsString = textView.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Clear existing search highlights
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        for highlight in highlights {
            guard highlight.range.location != NSNotFound,
                  NSMaxRange(highlight.range) <= nsString.length
            else { continue }
            let color: NSColor = highlight.isCurrent
                ? .systemOrange.withAlphaComponent(0.45)
                : .systemYellow.withAlphaComponent(0.3)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: highlight.range)
        }
    }

    private func makeParaStyle() -> NSMutableParagraphStyle {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = lineSpacing
        return paraStyle
    }

    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: makeParaStyle(),
        ]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isEditing = false
        var isAdjustingCursor = false
        var onTextChange: ((_ newText: String) -> Void)?
        var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?
        /// Tracks previous focus state to detect focus transitions.
        var wasFocused = false

        init(
            text: Binding<String>,
            onTextChange: ((_ newText: String) -> Void)?,
            onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?
        ) {
            _text = text
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? BlockNSTextView else { return }
            isEditing = true
            text = textView.string
            onTextChange?(textView.string)

            // Re-apply markdown styling after every text change
            if textView.markdownStyleEnabled, let ts = textView.textStorage {
                let savedRange = textView.selectedRange()
                textView.markdownStyler.invalidate()
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.lineSpacing = textView.baseLineSpacing
                textView.markdownStyler.restyleInline(
                    ts,
                    defaultFont: textView.baseFont,
                    defaultParaStyle: paraStyle,
                    defaultTextColor: textView.baseTextColor
                )
                // Restore cursor position (attribute changes may shift it)
                let clampedLoc = min(savedRange.location, ts.length)
                let clampedLen = min(savedRange.length, ts.length - clampedLoc)
                textView.setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
                // Update typing attributes at cursor for correct font inheritance
                textView.updateTypingAttributesAtCursor()
            }

            isEditing = false
        }

        func textDidBeginEditing(_: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_: Notification) {
            isEditing = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? BlockNSTextView else { return }

            // Skip only the delimiter-adjustment logic during re-entrant calls
            if !isAdjustingCursor, textView.markdownStyleEnabled {
                let currentRange = textView.selectedRange()
                if currentRange.length == 0,
                   let ts = textView.textStorage,
                   textView.markdownStyler.isInsideDelimiter(at: currentRange.location)
                {
                    isAdjustingCursor = true
                    let newLoc = textView.markdownStyler.skipDelimiter(from: currentRange.location, direction: +1)
                    textView.setSelectedRange(NSRange(location: min(newLoc, ts.length), length: 0))
                    isAdjustingCursor = false
                }
                textView.updateTypingAttributesAtCursor()
            }

            // Always fire the selection callback — even during re-entrant calls
            let range = textView.selectedRange()
            var contentRect: CGRect?
            if range.length > 0, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let viewRect = rect.offsetBy(dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)
                // Convert to content view coordinates
                if let contentView = textView.window?.contentView {
                    let contentCoords = textView.convert(viewRect, to: contentView)
                    if contentView.isFlipped {
                        // NSHostingView is flipped — Y is already from top, matches SwiftUI
                        contentRect = contentCoords
                    } else {
                        // Standard AppKit: flip Y manually
                        let flippedY = contentView.bounds.height - contentCoords.maxY
                        contentRect = CGRect(
                            x: contentCoords.origin.x,
                            y: flippedY,
                            width: contentCoords.width,
                            height: contentCoords.height
                        )
                    }
                }
            }
            onSelectionChange?(textView, range, contentRect)
        }
    }
}

// MARK: - MarkdownNSTextView

/// Base NSTextView subclass with WYSIWYG markdown editing support.
/// Provides inline formatting shortcuts (Cmd+B/I/U), smart delimiter deletion,
/// cursor-skipping past hidden delimiters, and typing attribute inheritance.
/// Subclassed by `BlockNSTextView` (block editor) and `TableCellNSTextView` (table cells).
class MarkdownNSTextView: NSTextView {
    // MARK: - Markdown WYSIWYG

    /// Whether inline markdown styling (bold, italic, etc.) is active.
    var markdownStyleEnabled: Bool = false
    /// The MarkdownStyler instance for WYSIWYG rendering.
    let markdownStyler = MarkdownStyler()
    /// Base font for restyling.
    var baseFont: NSFont = .preferredFont(forTextStyle: .body)
    /// Base text color for restyling.
    var baseTextColor: NSColor = .labelColor
    /// Base line spacing for restyling.
    var baseLineSpacing: CGFloat = AppThemeConstants.lineSpacingDefault

    /// Updates typingAttributes to match the attributes at the current cursor position,
    /// so newly typed characters inherit the correct formatting (e.g., bold inside a bold region).
    func updateTypingAttributesAtCursor() {
        guard markdownStyleEnabled, let ts = textStorage else { return }
        let loc = selectedRange().location
        // Find a non-delimiter position to read attributes from
        var attrLoc = loc > 0 ? loc - 1 : 0
        // Skip backward past any delimiter characters
        while attrLoc > 0, markdownStyler.isInsideDelimiter(at: attrLoc) {
            attrLoc -= 1
        }
        // If still on a delimiter at position 0, try forward
        if markdownStyler.isInsideDelimiter(at: attrLoc) {
            attrLoc = loc
            while attrLoc < ts.length, markdownStyler.isInsideDelimiter(at: attrLoc) {
                attrLoc += 1
            }
        }
        guard attrLoc < ts.length else { return }
        let attrs = ts.attributes(at: attrLoc, effectiveRange: nil)
        // Build typing attributes from the existing attributes, preserving font and color
        var typing: [NSAttributedString.Key: Any] = [:]
        typing[.font] = attrs[.font] ?? baseFont
        typing[.foregroundColor] = attrs[.foregroundColor] ?? baseTextColor
        if let para = attrs[.paragraphStyle] {
            typing[.paragraphStyle] = para
        } else {
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = baseLineSpacing
            typing[.paragraphStyle] = paraStyle
        }
        // Don't inherit hidden font (delimiter) — use base font instead
        if let currentFont = typing[.font] as? NSFont, currentFont.pointSize < 1 {
            typing[.font] = baseFont
        }
        // Don't inherit clear color (hidden delimiter) — use base color
        if let currentColor = typing[.foregroundColor] as? NSColor, currentColor == .clear {
            typing[.foregroundColor] = baseTextColor
        }
        typingAttributes = typing
    }

    /// Prefer plain text on paste so markdown text is preserved
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        if markdownStyleEnabled {
            return [.string]
        }
        return super.readablePasteboardTypes
    }

    // MARK: - Keyboard Shortcuts for Formatting

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard markdownStyleEnabled,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift)
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "b":
            applyMarkdownFormatting("**")
            return true
        case "i":
            applyMarkdownFormatting("*")
            return true
        case "u":
            applyMarkdownFormatting("<u>")
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if markdownStyleEnabled,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
        {
            switch event.charactersIgnoringModifiers {
            case "b":
                applyMarkdownFormatting("**")
                return
            case "i":
                applyMarkdownFormatting("*")
                return
            case "u":
                applyMarkdownFormatting("<u>")
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Smart Backspace (Delimiter Deletion)

    override func deleteBackward(_ sender: Any?) {
        // Smart backspace: if character before cursor is a hidden delimiter,
        // remove both opening and closing delimiters to un-format the text.
        guard markdownStyleEnabled, selectedRange().length == 0 else {
            super.deleteBackward(sender)
            return
        }

        let loc = selectedRange().location
        guard loc > 0 else {
            super.deleteBackward(sender)
            return
        }

        let charBefore = loc - 1
        if let delimRange = markdownStyler.delimiterRange(containing: charBefore),
           let pairedRange = markdownStyler.pairedDelimiter(for: delimRange),
           let ts = textStorage
        {
            // Remove both delimiters in a single undo group (closing first to preserve offsets)
            let first = delimRange.location < pairedRange.location ? delimRange : pairedRange
            let second = delimRange.location < pairedRange.location ? pairedRange : delimRange

            undoManager?.beginUndoGrouping()
            ts.beginEditing()
            ts.replaceCharacters(in: second, with: "")
            ts.replaceCharacters(in: first, with: "")
            ts.endEditing()
            undoManager?.endUndoGrouping()

            setSelectedRange(NSRange(location: first.location, length: 0))
            didChangeText()
            return
        }

        super.deleteBackward(sender)
    }

    // MARK: - Delimiter Skipping

    /// After a cursor movement, skip past any hidden delimiter at the new position.
    func adjustCursorPastDelimiters(direction: Int) {
        guard markdownStyleEnabled else { return }
        let loc = selectedRange().location
        if markdownStyler.isInsideDelimiter(at: loc) {
            let newLoc = markdownStyler.skipDelimiter(from: loc, direction: direction)
            let clamped = max(0, min(newLoc, textStorage?.length ?? 0))
            setSelectedRange(NSRange(location: clamped, length: 0))
        }
    }

    /// For shift+arrow selection extension, skip the moving end past delimiters.
    func adjustSelectionPastDelimiters(direction: Int) {
        guard markdownStyleEnabled else { return }
        let range = selectedRange()
        let moving = direction > 0 ? NSMaxRange(range) : range.location
        if markdownStyler.isInsideDelimiter(at: moving) {
            let newMoving = markdownStyler.skipDelimiter(from: moving, direction: direction)
            let clamped = max(0, min(newMoving, textStorage?.length ?? 0))
            if direction > 0 {
                setSelectedRange(NSRange(location: range.location, length: clamped - range.location))
            } else {
                setSelectedRange(NSRange(location: clamped, length: NSMaxRange(range) - clamped))
            }
        }
    }

    override func moveRight(_ sender: Any?) {
        super.moveRight(sender)
        adjustCursorPastDelimiters(direction: +1)
    }

    override func moveLeft(_ sender: Any?) {
        super.moveLeft(sender)
        adjustCursorPastDelimiters(direction: -1)
    }

    override func moveForward(_ sender: Any?) {
        super.moveForward(sender)
        adjustCursorPastDelimiters(direction: +1)
    }

    override func moveBackward(_ sender: Any?) {
        super.moveBackward(sender)
        adjustCursorPastDelimiters(direction: -1)
    }

    override func moveWordRight(_ sender: Any?) {
        super.moveWordRight(sender)
        adjustCursorPastDelimiters(direction: +1)
    }

    override func moveWordLeft(_ sender: Any?) {
        super.moveWordLeft(sender)
        adjustCursorPastDelimiters(direction: -1)
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        super.moveRightAndModifySelection(sender)
        adjustSelectionPastDelimiters(direction: +1)
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
        super.moveLeftAndModifySelection(sender)
        adjustSelectionPastDelimiters(direction: -1)
    }

    // MARK: - Resize Handling

    override func setFrameSize(_ size: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(size)

        guard abs(oldWidth - size.width) > 0.1, let textContainer else { return }

        textContainer.containerSize = NSSize(
            width: max(0, size.width - textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Formatting

    func applyMarkdownFormatting(_ delimiter: String) {
        var range = selectedRange()
        let dLen = delimiter.count
        let nsString = string as NSString

        // No selection — either toggle off existing formatting or insert empty delimiters
        if range.length == 0 {
            if markdownStyleEnabled {
                // Check if cursor is inside an already-formatted region by looking for
                // delimiters surrounding the cursor position
                let loc = range.location
                if let closingDelim = findClosingDelimiter(delimiter, after: loc),
                   let openingDelim = findOpeningDelimiter(delimiter, before: loc)
                {
                    // Remove both delimiters to un-format
                    guard let ts = textStorage else { return }
                    undoManager?.beginUndoGrouping()
                    ts.beginEditing()
                    ts.replaceCharacters(in: closingDelim, with: "")
                    ts.replaceCharacters(in: openingDelim, with: "")
                    ts.endEditing()
                    undoManager?.endUndoGrouping()
                    setSelectedRange(NSRange(location: openingDelim.location, length: 0))
                    didChangeText()
                    return
                }
            }
            // Insert empty delimiters and place cursor between them
            let wrapped = "\(delimiter)\(delimiter)"
            insertText(wrapped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + dLen, length: 0))
            // Set typing attributes so text typed between delimiters uses the correct style
            var attrs = typingAttributes
            let fm = NSFontManager.shared
            switch delimiter {
            case "**":
                attrs[.font] = fm.convert(baseFont, toHaveTrait: .boldFontMask)
            case "*":
                attrs[.font] = fm.convert(baseFont, toHaveTrait: .italicFontMask)
            case "`":
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
            default:
                break
            }
            typingAttributes = attrs
            return
        }

        // With hidden delimiters, the visual selection may not include them.
        // Check if delimiters exist just outside the selection and expand if so.
        if markdownStyleEnabled {
            let beforeStart = range.location - dLen
            let afterEnd = NSMaxRange(range)
            if beforeStart >= 0, afterEnd + dLen <= nsString.length {
                let before = nsString.substring(with: NSRange(location: beforeStart, length: dLen))
                let after = nsString.substring(with: NSRange(location: afterEnd, length: dLen))
                if before == delimiter, after == delimiter {
                    range = NSRange(location: beforeStart, length: range.length + dLen * 2)
                }
            }
        }

        let selected = nsString.substring(with: range)

        // Check if already wrapped — toggle off
        if selected.hasPrefix(delimiter), selected.hasSuffix(delimiter), selected.count >= dLen * 2 {
            let unwrapped = String(selected.dropFirst(dLen).dropLast(dLen))
            insertText(unwrapped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: unwrapped.count))
        } else {
            let wrapped = "\(delimiter)\(selected)\(delimiter)"
            insertText(wrapped, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + dLen, length: selected.count))
        }
    }

    /// Finds a closing delimiter after the given position on the same line.
    func findClosingDelimiter(_ delimiter: String, after position: Int) -> NSRange? {
        let nsString = string as NSString
        guard position < nsString.length else { return nil }
        let lineRange = nsString.lineRange(for: NSRange(location: position, length: 0))
        let searchRange = NSRange(location: position, length: NSMaxRange(lineRange) - position)
        let found = nsString.range(of: delimiter, range: searchRange)
        return found.location != NSNotFound ? found : nil
    }

    /// Finds an opening delimiter before the given position on the same line.
    func findOpeningDelimiter(_ delimiter: String, before position: Int) -> NSRange? {
        let nsString = string as NSString
        guard position > 0 else { return nil }
        let lineRange = nsString.lineRange(for: NSRange(location: position, length: 0))
        let searchRange = NSRange(location: lineRange.location, length: position - lineRange.location)
        let found = nsString.range(of: delimiter, options: .backwards, range: searchRange)
        return found.location != NSNotFound ? found : nil
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: rect.height + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - BlockNSTextView

/// NSTextView subclass for block-level editing. Adds block navigation callbacks,
/// multi-block paste, slash commands, and suggestion click handling on top of MarkdownNSTextView.
final class BlockNSTextView: MarkdownNSTextView {
    var onEnter: ((_ cursorOffset: Int) -> Void)?
    var onBackspaceAtStart: (() -> Void)?
    var onArrowUp: ((_ cursorXPosition: CGFloat) -> Void)?
    var onArrowDown: ((_ cursorXPosition: CGFloat) -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onSlashAtStart: (() -> Void)?
    var onFocusGained: (() -> Void)?
    var onDeleteForwardAtEnd: (() -> Void)?
    /// Set in mouseDown when focus is gained via click — prevents applyFocus from overriding click position.
    var focusedViaClick = false
    var suggestions: [Suggestion] = []
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?
    var onMultiBlockPaste: ((_ markdown: String) -> Void)?
    var onSelectAllBlocks: (() -> Void)?
    var onShiftArrowUpAtTop: (() -> Void)?
    var onShiftArrowDownAtBottom: (() -> Void)?
    /// Auto-capitalize the first letter when the user starts typing in an empty block.
    var autoCapitalize: Bool = true
    /// When set, this NSTextView exposes itself as `AXHeading` with the given level (1-6)
    /// so VoiceOver rotor-by-heading navigation finds it. Paragraph / list blocks leave this nil.
    var headingLevel: Int? {
        didSet {
            guard oldValue != headingLevel else { return }
            // Tell AX that our role changed so assistive tech re-queries.
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        headingLevel != nil ? .staticText : super.accessibilityRole()
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        // macOS reports headings via the "AXHeading" subrole of AXStaticText.
        if headingLevel != nil {
            return NSAccessibility.Subrole(rawValue: "AXHeading")
        }
        return super.accessibilitySubrole()
    }

    override func accessibilityRoleDescription() -> String? {
        if let level = headingLevel {
            return "heading level \(level)"
        }
        return super.accessibilityRoleDescription()
    }

    /// Tracks which suggestion IDs were last underlined — avoids redundant reapplication.
    var lastAppliedSuggestionIDs: Set<UUID> = []
    /// Binding to the editor-wide goal column X position for vertical arrow navigation.
    var goalColumnXBinding: Binding<CGFloat?>?

    private var goalColumnX: CGFloat? {
        get { goalColumnXBinding?.wrappedValue }
        set { goalColumnXBinding?.wrappedValue = newValue }
    }

    // MARK: - Paste Sanitization

    static func sanitizePastedText(_ text: String) -> String {
        var result = text
        // Remove zero-width spaces and other invisible characters
        result = result.replacingOccurrences(of: "\u{200B}", with: "")
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        // Normalize line endings
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        // Collapse 3+ consecutive newlines to 2 (preserve paragraph breaks)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        // Trim trailing whitespace per line
        result = result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var trimmed = String(line)
                while trimmed.last?.isWhitespace == true {
                    trimmed.removeLast()
                }
                return trimmed
            }
            .joined(separator: "\n")
        // Trim leading/trailing whitespace from entire string
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Multi-Block Paste

    override func paste(_ sender: Any?) {
        guard markdownStyleEnabled,
              let pasteString = NSPasteboard.general.string(forType: .string)
        else {
            super.paste(sender)
            return
        }

        let cleaned = Self.sanitizePastedText(pasteString)
        guard !cleaned.isEmpty else { return }

        // Detect block-level markdown elements that should create new blocks
        let hasBlockElements = cleaned.contains("\n\n")
            || cleaned.contains("\n| ")
            || cleaned.contains("\n- ")
            || cleaned.contains("\n* ")
            || cleaned.contains("\n# ")
            || cleaned.contains("\n```")
            || cleaned.contains("\n> ")
            || cleaned.hasPrefix("| ")
            || cleaned.hasPrefix("- ")
            || cleaned.hasPrefix("* ")
            || cleaned.hasPrefix("# ")
            || cleaned.hasPrefix("```")
            || cleaned.hasPrefix("> ")

        if hasBlockElements, let onMultiBlockPaste {
            onMultiBlockPaste(cleaned)
        } else {
            // Single-line plain text insert — avoids NSTextView injecting foreign attributes
            let insertStr = cleaned.replacingOccurrences(of: "\n", with: " ")
            insertText(insertStr, replacementRange: selectedRange())
        }
    }

    // MARK: - Block Navigation

    override func insertNewline(_ sender: Any?) {
        guard let onEnter else {
            super.insertNewline(sender)
            return
        }
        let offset = selectedRange().location
        // Resign first-responder BEFORE triggering the split so any keystrokes posted
        // during the SwiftUI focus-transition window (state update → re-render → new
        // BlockNSTextView.becomeFirstResponder) don't get mis-routed into this now-wrong
        // text view. Without this, fast typing after Enter (60+ WPM + paste-like bursts)
        // can spill the first character into the previous block.
        window?.makeFirstResponder(nil)
        onEnter(offset)
    }

    override func deleteBackward(_ sender: Any?) {
        goalColumnX = nil
        if selectedRange().location == 0, selectedRange().length == 0 {
            onBackspaceAtStart?()
            return
        }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        goalColumnX = nil
        if selectedRange().location >= string.count, selectedRange().length == 0 {
            onDeleteForwardAtEnd?()
            return
        }
        super.deleteForward(sender)
    }

    override func moveUp(_ sender: Any?) {
        // Establish goal column on first vertical press
        if goalColumnX == nil {
            goalColumnX = cursorXPosition()
        }
        // If cursor is on the first line, move to previous block
        if isCursorOnFirstLine() {
            onArrowUp?(goalColumnX ?? cursorXPosition())
            return
        }
        // Within-block: use goal column for custom positioning
        if let targetOffset = offsetOnPreviousLine(goalX: goalColumnX ?? cursorXPosition()) {
            setSelectedRange(NSRange(location: targetOffset, length: 0))
        } else {
            super.moveUp(sender)
        }
    }

    override func moveDown(_ sender: Any?) {
        // Establish goal column on first vertical press
        if goalColumnX == nil {
            goalColumnX = cursorXPosition()
        }
        // If cursor is on the last line, move to next block
        if isCursorOnLastLine() {
            onArrowDown?(goalColumnX ?? cursorXPosition())
            return
        }
        // Within-block: use goal column for custom positioning
        if let targetOffset = offsetOnNextLine(goalX: goalColumnX ?? cursorXPosition()) {
            setSelectedRange(NSRange(location: targetOffset, length: 0))
        } else {
            super.moveDown(sender)
        }
    }

    /// Returns the X position of the cursor's insertion point relative to the text view.
    private func cursorXPosition() -> CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let loc = selectedRange().location
        let nsLength = (string as NSString).length
        guard nsLength > 0 else { return 0 }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(loc, nsLength - 1))
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        return rect.origin.x + textContainerOrigin.x
    }

    // MARK: - Goal Column Helpers

    /// Finds the character offset on the line above the current cursor that is closest to the given X.
    private func offsetOnPreviousLine(goalX: CGFloat) -> Int? {
        guard let layoutManager, textContainer != nil else { return nil }
        let loc = selectedRange().location
        let nsLength = (string as NSString).length
        guard nsLength > 0, loc > 0 else { return nil }

        // Get current line's glyph range
        let curGlyphIdx = layoutManager.glyphIndexForCharacter(at: min(loc, nsLength - 1))
        var currentLineGlyphRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: curGlyphIdx, effectiveRange: &currentLineGlyphRange)

        // If current line starts at glyph 0, there's no previous line
        if currentLineGlyphRange.location == 0 {
            return nil
        }

        // Get previous line's glyph range
        var prevLineGlyphRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: currentLineGlyphRange.location - 1, effectiveRange: &prevLineGlyphRange)
        let prevLineCharRange = layoutManager.characterRange(forGlyphRange: prevLineGlyphRange, actualGlyphRange: nil)

        return closestOffset(toX: goalX, inCharRange: prevLineCharRange)
    }

    /// Finds the character offset on the line below the current cursor that is closest to the given X.
    private func offsetOnNextLine(goalX: CGFloat) -> Int? {
        guard let layoutManager, textContainer != nil else { return nil }
        let loc = selectedRange().location
        let nsLength = (string as NSString).length
        guard nsLength > 0 else { return nil }

        // Get current line's glyph range
        let curGlyphIdx = layoutManager.glyphIndexForCharacter(at: min(loc, nsLength - 1))
        var currentLineGlyphRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: curGlyphIdx, effectiveRange: &currentLineGlyphRange)

        // If current line ends at the last glyph, there's no next line
        let nextGlyphStart = NSMaxRange(currentLineGlyphRange)
        if nextGlyphStart >= layoutManager.numberOfGlyphs {
            return nil
        }

        // Get next line's glyph range
        var nextLineGlyphRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: nextGlyphStart, effectiveRange: &nextLineGlyphRange)
        let nextLineCharRange = layoutManager.characterRange(forGlyphRange: nextLineGlyphRange, actualGlyphRange: nil)

        return closestOffset(toX: goalX, inCharRange: nextLineCharRange)
    }

    /// Finds the character offset within a character range whose X position is closest to targetX.
    private func closestOffset(toX targetX: CGFloat, inCharRange charRange: NSRange) -> Int {
        guard let layoutManager, let textContainer else { return charRange.location }
        let containerOriginX = textContainerOrigin.x
        let nsLength = (string as NSString).length
        var bestOffset = charRange.location
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        let end = NSMaxRange(charRange)
        for charOffset in charRange.location ... end {
            let clampedChar = min(charOffset, max(0, nsLength - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedChar)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            let x = rect.origin.x + containerOriginX
            let distance = abs(x - targetX)
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = charOffset
            }
        }
        return min(bestOffset, nsLength)
    }

    // MARK: - Goal Column Reset on Horizontal Movement

    override func moveLeft(_ sender: Any?) {
        goalColumnX = nil
        super.moveLeft(sender)
    }

    override func moveRight(_ sender: Any?) {
        goalColumnX = nil
        super.moveRight(sender)
    }

    override func moveWordLeft(_ sender: Any?) {
        goalColumnX = nil
        super.moveWordLeft(sender)
    }

    override func moveWordRight(_ sender: Any?) {
        goalColumnX = nil
        super.moveWordRight(sender)
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        goalColumnX = nil
        super.moveToBeginningOfLine(sender)
    }

    override func moveToEndOfLine(_ sender: Any?) {
        goalColumnX = nil
        super.moveToEndOfLine(sender)
    }

    override func insertTab(_ sender: Any?) {
        if let onTab {
            onTab()
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if let onBackTab {
            onBackTab()
            return
        }
        super.insertBacktab(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        goalColumnX = nil
        if let str = string as? String, str == "/", self.string.isEmpty {
            onSlashAtStart?()
            return
        }
        // Auto-capitalize first character when starting a new block
        if autoCapitalize,
           let str = string as? String,
           self.string.isEmpty,
           selectedRange().location == 0,
           let first = str.first, first.isLetter
        {
            let capitalized = str.prefix(1).uppercased() + str.dropFirst()
            super.insertText(capitalized, replacementRange: replacementRange)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Cmd+A → Select All Blocks

    override func selectAll(_ sender: Any?) {
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        // If already fully selected or empty → escalate to all-blocks selection
        if selectedRange() == fullRange || string.isEmpty {
            onSelectAllBlocks?()
            return
        }
        super.selectAll(sender)
    }

    // MARK: - Shift+Arrow at Block Boundaries

    override func moveUpAndModifySelection(_ sender: Any?) {
        if isCursorOnFirstLine() {
            onShiftArrowUpAtTop?()
            return
        }
        super.moveUpAndModifySelection(sender)
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        if isCursorOnLastLine() {
            onShiftArrowDownAtBottom?()
            return
        }
        super.moveDownAndModifySelection(sender)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusGained?()
        }
        return result
    }

    // MARK: - Suggestion Click

    override func mouseDown(with event: NSEvent) {
        goalColumnX = nil
        let point = convert(event.locationInWindow, from: nil)
        if let suggestion = suggestionAtPoint(point) {
            showSuggestionPopover(suggestion, at: point)
            return
        }

        // If not editable (unfocused block), make editable and become first responder
        // so NSTextView processes the full mouseDown interaction (including drag-to-select)
        if !isEditable {
            isEditable = true
            focusedViaClick = true
            // Force restyle to prevent delimiter flash during focus transition
            if markdownStyleEnabled, let ts = textStorage {
                markdownStyler.invalidate()
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.lineSpacing = baseLineSpacing
                markdownStyler.restyleInline(ts, defaultFont: baseFont, defaultParaStyle: paraStyle, defaultTextColor: baseTextColor)
            }
            window?.makeFirstResponder(self)
        }

        super.mouseDown(with: event)
    }

    private func suggestionAtPoint(_ point: NSPoint) -> Suggestion? {
        guard let layoutManager, let textContainer else { return nil }
        let textPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let charIndex = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let nsString = string as NSString
        for suggestion in suggestions {
            let range = nsString.range(of: suggestion.original)
            if range.location != NSNotFound, NSLocationInRange(charIndex, range) {
                return suggestion
            }
        }
        return nil
    }

    private func showSuggestionPopover(_ suggestion: Suggestion, at point: NSPoint) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 120)
        popover.contentViewController = NSHostingController(
            rootView: SuggestionPopoverContent(
                suggestion: suggestion,
                onAccept: { [weak self] in
                    popover.close()
                    // Apply the fix
                    if let self {
                        let nsString = string as NSString
                        let range = nsString.range(of: suggestion.original)
                        if range.location != NSNotFound {
                            insertText(suggestion.replacement, replacementRange: range)
                        }
                    }
                    self?.onSuggestionAccepted?(suggestion)
                },
                onDismiss: { [weak self] in
                    popover.close()
                    self?.onSuggestionDismissed?(suggestion)
                }
            )
        )
        let rect = NSRect(origin: point, size: NSSize(width: 1, height: 1))
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    // MARK: - Line Detection

    private func isCursorOnFirstLine() -> Bool {
        guard let layoutManager, textContainer != nil else { return false }
        let loc = selectedRange().location
        if loc == 0 {
            return true
        }
        let glyphIdx = layoutManager.glyphIndexForCharacter(at: loc)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineRange)
        // First line if the line range starts at 0
        return lineRange.location == 0
    }

    private func isCursorOnLastLine() -> Bool {
        guard let layoutManager, textContainer != nil else { return false }
        let loc = selectedRange().location
        if loc >= string.count {
            return true
        }
        let glyphIdx = layoutManager.glyphIndexForCharacter(at: loc)
        var lineRange = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineRange)
        // Last line if the end of this line range reaches the end of text
        return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
    }
}

// MARK: - SuggestionPopoverContent

/// Compact popover shown when clicking on a suggestion underline.
private struct SuggestionPopoverContent: View {
    let suggestion: Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(suggestion.type.categoryDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(suggestion.type.categoryColor)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
            }

            Text(suggestion.explanation)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                // Show the replacement
                Text(suggestion.replacement)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)

                Spacer()

                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)

                Button("Dismiss") { onDismiss() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
