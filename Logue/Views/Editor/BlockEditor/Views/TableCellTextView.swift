import AppKit
import SwiftUI

// MARK: - TableCellNSTextView

/// Lightweight NSTextView subclass for table cell editing.
/// Inherits WYSIWYG markdown formatting from MarkdownNSTextView,
/// adds table-cell-specific navigation (Tab, Enter, Escape).
final class TableCellNSTextView: MarkdownNSTextView {
    var onTab: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func insertTab(_ sender: Any?) {
        onTab?()
    }

    override func insertNewline(_ sender: Any?) {
        onSubmit?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func paste(_ sender: Any?) {
        guard markdownStyleEnabled,
              let pasteString = NSPasteboard.general.string(forType: .string)
        else {
            super.paste(sender)
            return
        }
        // Table cells: always single-line plain text
        let cleaned = BlockNSTextView.sanitizePastedText(pasteString)
            .replacingOccurrences(of: "\n", with: " ")
        insertText(cleaned, replacementRange: selectedRange())
    }
}

// MARK: - TableCellTextView

/// NSViewRepresentable wrapper for editing a single table cell with WYSIWYG markdown.
/// Supports Cmd+B/I/U formatting, hidden delimiters, and cell navigation callbacks.
struct TableCellTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize)
    var isHeader: Bool = false
    var isFocused: Bool = false
    var onTab: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?

    func makeNSView(context: Context) -> TableCellNSTextView {
        let textView = TableCellNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
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

        let cellFont = isHeader ? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font
        textView.font = cellFont
        textView.typingAttributes = makeTypingAttributes(cellFont)
        textView.markdownStyleEnabled = true
        textView.baseFont = cellFont
        textView.baseTextColor = .labelColor
        textView.baseLineSpacing = 3.5

        // Set initial text and apply markdown styling
        textView.string = text
        if let ts = textView.textStorage {
            textView.markdownStyler.restyleInline(
                ts, defaultFont: cellFont,
                defaultParaStyle: makeParaStyle(),
                defaultTextColor: .labelColor
            )
        }

        // Store callbacks
        textView.onTab = onTab
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape

        return textView
    }

    func updateNSView(_ textView: TableCellNSTextView, context: Context) {
        // Update callbacks
        textView.onTab = onTab
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        context.coordinator.onSelectionChange = onSelectionChange

        // Update text if it changed externally (not from user typing)
        if textView.string != text, !context.coordinator.isEditing {
            textView.string = text
            let cellFont = isHeader ? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font
            if let ts = textView.textStorage {
                textView.markdownStyler.invalidate()
                textView.markdownStyler.restyleInline(
                    ts, defaultFont: cellFont,
                    defaultParaStyle: makeParaStyle(),
                    defaultTextColor: .labelColor
                )
            }
        }

        // Handle focus
        if isFocused, textView.window?.firstResponder !== textView {
            if textView.window != nil {
                textView.window?.makeFirstResponder(textView)
                // Place cursor at end
                textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            } else {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                    textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    private func makeParaStyle() -> NSMutableParagraphStyle {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 3.5
        return paraStyle
    }

    private func makeTypingAttributes(_ cellFont: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: cellFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: makeParaStyle(),
        ]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isEditing = false
        var isAdjustingCursor = false
        var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?

        init(
            text: Binding<String>,
            onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?
        ) {
            _text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? TableCellNSTextView else { return }
            isEditing = true
            text = textView.string

            // Re-apply markdown styling after every text change
            if let ts = textView.textStorage {
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
                // Restore cursor position
                let clampedLoc = min(savedRange.location, ts.length)
                let clampedLen = min(savedRange.length, ts.length - clampedLoc)
                textView.setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
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
            guard let textView = notification.object as? TableCellNSTextView else { return }

            // Delimiter skipping
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

            // Fire selection callback for toolbar positioning
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
