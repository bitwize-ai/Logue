// swiftlint:disable file_length
import AppKit
import Markdown

// MARK: - MarkdownStyler

/// Parses markdown text and applies live NSAttributedString styling to an NSTextStorage.
/// Uses Apple's swift-markdown (cmark-gfm) for AST parsing and a MarkupWalker visitor
/// to map AST nodes to text attributes.
final class MarkdownStyler {
    // MARK: - Style Config

    /// Pre-computed fonts and colors for each markdown element, derived from a base font size.
    struct StyleConfig {
        let bodyFont: NSFont
        let bodyColor: NSColor
        let bodyParaStyle: NSMutableParagraphStyle

        let h1Font: NSFont
        let h2Font: NSFont
        let h3Font: NSFont
        let h1ParaStyle: NSParagraphStyle
        let h2ParaStyle: NSParagraphStyle
        let h3ParaStyle: NSParagraphStyle

        let boldFont: NSFont
        let italicFont: NSFont
        let boldItalicFont: NSFont

        let codeFont: NSFont
        let codeBackground: NSColor

        let quoteColor: NSColor
        let linkColor: NSColor
        let delimiterColor: NSColor
        let listMarkerColor: NSColor
        let checkboxUncheckedColor: NSColor
        let checkboxCheckedColor: NSColor
        /// Near-zero-width font used to collapse hidden delimiters.
        let hiddenFont: NSFont

        init(baseFont: NSFont) {
            let baseSize = baseFont.pointSize
            bodyFont = baseFont
            bodyColor = .labelColor
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = AppThemeConstants.lineSpacingDefault
            paraStyle.paragraphSpacing = AppThemeConstants.bodyParagraphSpacing
            bodyParaStyle = paraStyle

            h1Font = .systemFont(ofSize: baseSize + AppThemeConstants.headingSizeH1, weight: .bold)
            h2Font = .systemFont(ofSize: baseSize + AppThemeConstants.headingSizeH2, weight: .semibold)
            h3Font = .systemFont(ofSize: baseSize + AppThemeConstants.headingSizeH3, weight: .medium)

            let h1Style = NSMutableParagraphStyle()
            h1Style.lineSpacing = AppThemeConstants.lineSpacingDefault
            h1Style.paragraphSpacingBefore = AppThemeConstants.headingSpacingBeforeH1
            h1Style.paragraphSpacing = AppThemeConstants.headingSpacingAfterH1
            h1ParaStyle = h1Style

            let h2Style = NSMutableParagraphStyle()
            h2Style.lineSpacing = AppThemeConstants.lineSpacingDefault
            h2Style.paragraphSpacingBefore = AppThemeConstants.headingSpacingBeforeH2
            h2Style.paragraphSpacing = AppThemeConstants.headingSpacingAfterH2
            h2ParaStyle = h2Style

            let h3Style = NSMutableParagraphStyle()
            h3Style.lineSpacing = AppThemeConstants.lineSpacingDefault
            h3Style.paragraphSpacingBefore = AppThemeConstants.headingSpacingBeforeH3
            h3Style.paragraphSpacing = AppThemeConstants.headingSpacingAfterH3
            h3ParaStyle = h3Style

            boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            let bi = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            boldItalicFont = NSFontManager.shared.convert(bi, toHaveTrait: .italicFontMask)

            codeFont = NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
            codeBackground = NSColor.labelColor.withAlphaComponent(0.06)

            quoteColor = .secondaryLabelColor
            linkColor = NSColor(AppThemeConstants.accent)
            delimiterColor = .tertiaryLabelColor
            listMarkerColor = .secondaryLabelColor
            checkboxUncheckedColor = .tertiaryLabelColor
            checkboxCheckedColor = NSColor(AppThemeConstants.accent)
            hiddenFont = .systemFont(ofSize: 0.01)
        }
    }

    // MARK: - Marker Info

    /// Info about a list marker that needs visual replacement (bullet dot, checkbox).
    struct MarkerInfo {
        let range: NSRange
        let type: String // "bullet", "checkboxUnchecked", "checkboxChecked"
        let nestingDepth: Int // 0 for non-list, 1+ for list items
    }

    // MARK: - State

    private var lastHash: Int = 0
    private var cachedConfig: StyleConfig?
    private var cachedFontSize: CGFloat = 0

    /// Ranges of markdown syntax delimiters (e.g. `#`, `**`, `*`, `` ` ``, `~~`, `>`).
    /// Populated after each `restyle()` call.
    private(set) var delimiterRanges: [NSRange] = []

    /// Ranges of list markers that get visual replacements (bullets, checkboxes).
    /// Populated after each `restyle()` call.
    private(set) var markerRanges: [MarkerInfo] = []

    /// The line range currently showing visible delimiters, or nil if none.
    private var revealedLineRange: NSRange?

    // MARK: - Delimiter Queries

    /// Returns true if the given character index falls inside any delimiter range.
    func isInsideDelimiter(at index: Int) -> Bool {
        delimiterRanges.contains { NSLocationInRange(index, $0) }
    }

    /// Returns the delimiter range containing the given index, or nil.
    func delimiterRange(containing index: Int) -> NSRange? {
        delimiterRanges.first { NSLocationInRange(index, $0) }
    }

    /// Given that `index` is inside a delimiter, returns the next position past
    /// the delimiter in the given direction (+1 forward, -1 backward).
    func skipDelimiter(from index: Int, direction: Int) -> Int {
        guard let range = delimiterRange(containing: index) else { return index }
        return direction > 0 ? NSMaxRange(range) : range.location
    }

    /// Finds the paired delimiter for a given delimiter range.
    /// Delimiters are collected in pairs: [opening, closing, opening, closing, ...].
    func pairedDelimiter(for range: NSRange) -> NSRange? {
        guard let idx = delimiterRanges.firstIndex(of: range) else { return nil }
        if idx % 2 == 0 {
            return idx + 1 < delimiterRanges.count ? delimiterRanges[idx + 1] : nil
        } else {
            return idx > 0 ? delimiterRanges[idx - 1] : nil
        }
    }

    // MARK: - Public API

    /// Lightweight inline-only restyle for per-block usage in the block editor.
    /// Only processes inline markdown (bold, italic, strikethrough, code, links) —
    /// skips block-level elements (headings, code fences, lists, tables, thematic breaks)
    /// since the block model already handles those.
    func restyleInline(_ textStorage: NSTextStorage, defaultFont: NSFont, defaultParaStyle: NSMutableParagraphStyle, defaultTextColor: NSColor) {
        let string = textStorage.string
        let hash = string.hashValue

        // Skip if unchanged
        if hash == lastHash, cachedFontSize == defaultFont.pointSize {
            return
        }
        lastHash = hash
        cachedFontSize = defaultFont.pointSize
        revealedLineRange = nil

        // Build or reuse style config
        if cachedConfig == nil || cachedConfig?.bodyFont.pointSize != defaultFont.pointSize {
            cachedConfig = StyleConfig(baseFont: defaultFont)
        }
        guard let config = cachedConfig else { return }

        // Parse markdown AST
        let document = Document(parsing: string, options: [.disableSmartOpts])

        // Build line offsets for SourceRange → NSRange conversion
        let lineOffsets = Self.buildLineOffsets(string)

        // Reset all attributes to defaults
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else {
            delimiterRanges = []
            markerRanges = []
            return
        }

        textStorage.beginEditing()

        textStorage.setAttributes([
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ], range: fullRange)

        // Walk AST with inline-only visitor (skips block-level styling)
        var visitor = InlineAttributeVisitor(
            textStorage: textStorage,
            string: string,
            lineOffsets: lineOffsets,
            config: config
        )
        visitor.visit(document)

        // Store and hide delimiters
        delimiterRanges = visitor.collectedDelimiterRanges
        markerRanges = []

        for range in delimiterRanges where NSMaxRange(range) <= textStorage.length {
            textStorage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: config.hiddenFont,
            ], range: range)
        }

        textStorage.endEditing()
    }

    /// Force a re-restyle on next call (used when block text is updated externally).
    func invalidate() {
        lastHash = 0
    }

    /// Re-parse and restyle the entire text storage.
    /// Skips work if the text hasn't changed since the last call.
    func restyle(_ textStorage: NSTextStorage, defaultFont: NSFont, defaultParaStyle: NSMutableParagraphStyle, defaultTextColor: NSColor) {
        let string = textStorage.string
        let hash = string.hashValue

        // Skip if unchanged
        if hash == lastHash, cachedFontSize == defaultFont.pointSize {
            return
        }
        lastHash = hash
        cachedFontSize = defaultFont.pointSize
        revealedLineRange = nil

        // Build or reuse style config
        if cachedConfig == nil || cachedConfig?.bodyFont.pointSize != defaultFont.pointSize {
            cachedConfig = StyleConfig(baseFont: defaultFont)
        }
        guard let config = cachedConfig else { return }

        // Parse markdown AST
        let document = Document(parsing: string)

        // Build line offsets for SourceRange → NSRange conversion
        let lineOffsets = Self.buildLineOffsets(string)

        // Reset all attributes to defaults
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else {
            delimiterRanges = []
            return
        }

        textStorage.beginEditing()

        // Preserve attachment attributes before resetting (table overlays use NSTextAttachment)
        var savedAttachments: [(NSRange, NSTextAttachment)] = []
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            if let attachment = value as? NSTextAttachment {
                savedAttachments.append((range, attachment))
            }
        }

        textStorage.setAttributes([
            .font: defaultFont,
            .foregroundColor: defaultTextColor,
            .paragraphStyle: defaultParaStyle,
        ], range: fullRange)

        // Restore attachment attributes that were wiped by setAttributes
        for (range, attachment) in savedAttachments where NSMaxRange(range) <= textStorage.length {
            textStorage.addAttribute(.attachment, value: attachment, range: range)
        }

        // Walk AST and apply styles (visitor collects delimiter ranges)
        var visitor = AttributeVisitor(
            textStorage: textStorage,
            string: string,
            lineOffsets: lineOffsets,
            config: config
        )
        visitor.visit(document)

        // Store and hide delimiters + markers
        delimiterRanges = visitor.collectedDelimiterRanges
        markerRanges = visitor.collectedMarkerRanges
        hideAllDelimitersAndMarkers(textStorage: textStorage, config: config)

        textStorage.endEditing()
    }

    /// Hides all delimiter and marker ranges by default (tiny font + clear color).
    private func hideAllDelimitersAndMarkers(textStorage: NSTextStorage, config: StyleConfig) {
        for range in delimiterRanges where NSMaxRange(range) <= textStorage.length {
            textStorage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: config.hiddenFont,
            ], range: range)
        }

        for marker in markerRanges where NSMaxRange(marker.range) <= textStorage.length {
            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.clear,
                .listMarkerType: marker.type,
            ]
            if marker.type == "bullet" {
                attrs[.kern] = 3.0
            }
            if marker.type == "heading" || marker.type == "tableSeparator" {
                attrs[.font] = config.hiddenFont
            }
            textStorage.addAttributes(attrs, range: marker.range)
        }
    }

    /// Reveals delimiters on the line containing `caretLocation` and hides all others.
    /// Call this after restyle and on every selection/cursor change.
    func revealDelimiters(onLineContaining caretLocation: Int, in textStorage: NSTextStorage) {
        guard !delimiterRanges.isEmpty || !markerRanges.isEmpty else { return }
        let nsString = textStorage.string as NSString
        guard nsString.length > 0 else { return }

        let safeLoc = min(max(0, caretLocation), max(0, nsString.length - 1))
        let lineRange = nsString.lineRange(for: NSRange(location: safeLoc, length: 0))

        // Skip if already revealing this exact line
        if let revealed = revealedLineRange, revealed == lineRange {
            return
        }
        guard let config = cachedConfig else { return }

        textStorage.beginEditing()

        // Hide previously revealed line, reveal current line
        hideDelimitersOnOldLine(textStorage: textStorage, config: config)
        revealDelimitersOnLine(lineRange, textStorage: textStorage, config: config)
        hideTableMarkersOnOldLine(textStorage: textStorage, config: config)
        revealTableMarkersOnLine(lineRange, textStorage: textStorage, config: config)

        revealedLineRange = lineRange
        textStorage.endEditing()
    }

    private func hideDelimitersOnOldLine(textStorage: NSTextStorage, config: StyleConfig) {
        guard let oldLine = revealedLineRange else { return }
        for range in delimiterRanges where NSIntersectionRange(range, oldLine).length > 0 {
            guard NSMaxRange(range) <= textStorage.length else { continue }
            textStorage.addAttributes([.foregroundColor: NSColor.clear, .font: config.hiddenFont], range: range)
        }
    }

    private func revealDelimitersOnLine(_ lineRange: NSRange, textStorage: NSTextStorage, config: StyleConfig) {
        for range in delimiterRanges where NSIntersectionRange(range, lineRange).length > 0 {
            guard NSMaxRange(range) <= textStorage.length else { continue }
            textStorage.addAttributes([.foregroundColor: config.delimiterColor, .font: config.bodyFont], range: range)
        }
    }

    private func hideTableMarkersOnOldLine(textStorage: NSTextStorage, config: StyleConfig) {
        guard let oldLine = revealedLineRange else { return }
        for marker in markerRanges where NSIntersectionRange(marker.range, oldLine).length > 0 {
            guard NSMaxRange(marker.range) <= textStorage.length else { continue }
            switch marker.type {
            case "tablePipe", "tableSeparator":
                break // Table markers always stay hidden — never revealed
            case "divider":
                textStorage.addAttributes([.foregroundColor: NSColor.clear, .font: config.hiddenFont], range: marker.range)
            default:
                if marker.type.hasPrefix("numberedList:") {
                    textStorage.addAttributes([.foregroundColor: NSColor.clear], range: marker.range)
                }
            }
        }
    }

    private func revealTableMarkersOnLine(_ lineRange: NSRange, textStorage: NSTextStorage, config: StyleConfig) {
        for marker in markerRanges where NSIntersectionRange(marker.range, lineRange).length > 0 {
            guard NSMaxRange(marker.range) <= textStorage.length else { continue }
            switch marker.type {
            case "tablePipe", "tableSeparator":
                break // Table markers always stay hidden — table grid stays rendered
            case "divider":
                textStorage.addAttributes([.foregroundColor: config.delimiterColor, .font: config.bodyFont], range: marker.range)
            default:
                if marker.type.hasPrefix("numberedList:") {
                    textStorage.addAttributes([.foregroundColor: config.listMarkerColor], range: marker.range)
                }
            }
        }
    }

    // MARK: - Line Offset Builder

    /// Builds an array where `lineOffsets[i]` is the UTF-8 byte offset of the start of line `i` (0-indexed).
    static func buildLineOffsets(_ string: String) -> [Int] {
        var offsets = [0]
        var byteOffset = 0
        for byte in string.utf8 {
            byteOffset += 1
            if byte == UInt8(ascii: "\n") {
                offsets.append(byteOffset)
            }
        }
        return offsets
    }
}

// MARK: - NSRange Conversion

/// Convert a swift-markdown SourceRange to an NSRange in the given string.
/// SourceLocation uses 1-indexed lines and 1-indexed UTF-8 byte columns.
func nsRange(from sourceRange: SourceRange, in string: String, lineOffsets: [Int]) -> NSRange? {
    let startLine = sourceRange.lowerBound.line - 1
    let endLine = sourceRange.upperBound.line - 1

    guard startLine >= 0, startLine < lineOffsets.count,
          endLine >= 0, endLine < lineOffsets.count
    else { return nil }

    let startUTF8 = lineOffsets[startLine] + (sourceRange.lowerBound.column - 1)
    let endUTF8 = lineOffsets[endLine] + (sourceRange.upperBound.column - 1)

    let utf8View = string.utf8
    guard startUTF8 >= 0, endUTF8 >= startUTF8,
          let startIdx = utf8View.index(utf8View.startIndex, offsetBy: startUTF8, limitedBy: utf8View.endIndex),
          let endIdx = utf8View.index(utf8View.startIndex, offsetBy: endUTF8, limitedBy: utf8View.endIndex)
    else { return nil }

    return NSRange(startIdx ..< endIdx, in: string)
}

// MARK: - AttributeVisitor

/// Walks the markdown AST and applies NSAttributedString attributes to the text storage.
/// Delimiter ranges are collected (not colored) — the caller hides/reveals them.
private struct AttributeVisitor: MarkupWalker {
    let textStorage: NSTextStorage
    let string: String
    let lineOffsets: [Int]
    let config: MarkdownStyler.StyleConfig

    // Track nested strong/emphasis for bold-italic combinations
    var isInsideStrong = false
    var isInsideEmphasis = false

    /// Track list nesting depth (1 = top-level, 2 = nested once, etc.)
    var listNestingDepth: Int = 0

    /// Accumulated delimiter ranges to be hidden/revealed by the styler.
    var collectedDelimiterRanges: [NSRange] = []

    /// Accumulated marker ranges for visual replacement (bullets, checkboxes).
    var collectedMarkerRanges: [MarkdownStyler.MarkerInfo] = []

    // MARK: - Headings

    mutating func visitHeading(_ heading: Heading) {
        guard let range = resolveRange(heading) else {
            descendInto(heading)
            return
        }

        let font: NSFont
        let paraStyle: NSParagraphStyle
        switch heading.level {
        case 1:
            font = config.h1Font
            paraStyle = config.h1ParaStyle
        case 2:
            font = config.h2Font
            paraStyle = config.h2ParaStyle
        default:
            font = config.h3Font
            paraStyle = config.h3ParaStyle
        }

        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: range)

        // Collect the leading `#` characters as a marker (always hidden, never revealed on hover)
        let lineText = (string as NSString).substring(with: range)
        if let hashEnd = lineText.firstIndex(where: { $0 != "#" && $0 != " " }) {
            let prefixLen = lineText.distance(from: lineText.startIndex, to: hashEnd)
            if prefixLen > 0 {
                collectedMarkerRanges.append(
                    MarkdownStyler.MarkerInfo(range: NSRange(location: range.location, length: prefixLen), type: "heading", nestingDepth: 0)
                )
            }
        }

        descendInto(heading)
    }

    // MARK: - Strong (Bold)

    mutating func visitStrong(_ strong: Strong) {
        guard let range = resolveRange(strong) else {
            descendInto(strong)
            return
        }

        let wasInsideStrong = isInsideStrong
        isInsideStrong = true

        let font = isInsideEmphasis ? config.boldItalicFont : config.boldFont
        textStorage.addAttribute(.font, value: font, range: range)

        // Collect `**` delimiters (2 chars at start and end)
        collectDelimiters(in: range, prefixLen: 2, suffixLen: 2)

        descendInto(strong)
        isInsideStrong = wasInsideStrong
    }

    // MARK: - Emphasis (Italic)

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        guard let range = resolveRange(emphasis) else {
            descendInto(emphasis)
            return
        }

        let wasInsideEmphasis = isInsideEmphasis
        isInsideEmphasis = true

        let font = isInsideStrong ? config.boldItalicFont : config.italicFont
        textStorage.addAttribute(.font, value: font, range: range)

        // Collect `*` delimiters (1 char at start and end)
        collectDelimiters(in: range, prefixLen: 1, suffixLen: 1)

        descendInto(emphasis)
        isInsideEmphasis = wasInsideEmphasis
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        guard let range = resolveRange(strikethrough) else {
            descendInto(strikethrough)
            return
        }

        textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        // Collect `~~` delimiters
        collectDelimiters(in: range, prefixLen: 2, suffixLen: 2)

        descendInto(strikethrough)
    }

    // MARK: - Inline Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = resolveRange(inlineCode) else { return }

        textStorage.addAttributes([
            .font: config.codeFont,
            .backgroundColor: config.codeBackground,
        ], range: range)

        // Collect backtick delimiters
        collectDelimiters(in: range, prefixLen: 1, suffixLen: 1)
    }

    // MARK: - Code Block

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = resolveRange(codeBlock) else { return }

        let codeParaStyle = NSMutableParagraphStyle()
        codeParaStyle.lineSpacing = 2
        codeParaStyle.paragraphSpacingBefore = AppThemeConstants.codeBlockSpacingBefore
        codeParaStyle.paragraphSpacing = AppThemeConstants.codeBlockSpacingAfter
        textStorage.addAttributes([
            .font: config.codeFont,
            .foregroundColor: config.quoteColor,
            .paragraphStyle: codeParaStyle,
        ], range: range)
        textStorage.addAttribute(.codeBlockRange, value: true, range: range)

        // Apply syntax highlighting if a language is specified
        let language = codeBlock.language ?? ""
        if !language.isEmpty {
            textStorage.addAttribute(.codeBlockLanguage, value: language, range: range)
        }
        if !language.isEmpty {
            // Find the content range (skip the opening fence line)
            let codeText = (string as NSString).substring(with: range)
            if let firstNewline = codeText.firstIndex(of: "\n") {
                let fenceLen = codeText.distance(from: codeText.startIndex, to: firstNewline) + 1
                // Find closing fence
                let contentStart = range.location + fenceLen
                let closingFenceLen = codeText.hasSuffix("```\n") ? 4 : (codeText.hasSuffix("```") ? 3 : 0)
                let contentLen = range.length - fenceLen - closingFenceLen
                if contentLen > 0 {
                    let contentRange = NSRange(location: contentStart, length: contentLen)
                    CodeSyntaxHighlighter.highlight(textStorage, range: contentRange, language: language)
                }
            }
        }

        // Collect the opening and closing fence lines as delimiters
        let codeStr = (string as NSString).substring(with: range)
        if let firstNL = codeStr.firstIndex(of: "\n") {
            let fenceLen = codeStr.distance(from: codeStr.startIndex, to: firstNL)
            collectedDelimiterRanges.append(NSRange(location: range.location, length: fenceLen))
        }
        // Closing fence
        let trimmed = codeStr.hasSuffix("\n") ? String(codeStr.dropLast()) : codeStr
        if let lastNL = trimmed.lastIndex(of: "\n") {
            let closingStart = trimmed.distance(from: trimmed.startIndex, to: lastNL) + 1
            let closingLen = trimmed.count - closingStart
            if closingLen > 0 {
                collectedDelimiterRanges.append(NSRange(location: range.location + closingStart, length: closingLen))
            }
        }
    }

    // MARK: - Block Quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = resolveRange(blockQuote) else {
            descendInto(blockQuote)
            return
        }

        textStorage.addAttribute(.foregroundColor, value: config.quoteColor, range: range)
        textStorage.addAttribute(.blockQuoteRange, value: true, range: range)

        // Apply indented paragraph style
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = AppThemeConstants.lineSpacingDefault
        paraStyle.headIndent = AppThemeConstants.blockQuoteIndent
        paraStyle.firstLineHeadIndent = AppThemeConstants.blockQuoteIndent
        paraStyle.paragraphSpacingBefore = AppThemeConstants.blockQuoteSpacingBefore
        paraStyle.paragraphSpacing = AppThemeConstants.blockQuoteSpacingAfter
        textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: range)

        // Collect the `>` delimiter at start of each line in the quote
        let nsString = string as NSString
        let quoteText = nsString.substring(with: range)
        var searchStart = 0
        for line in quoteText.components(separatedBy: "\n") {
            if line.hasPrefix(">") {
                let prefixLen = line.hasPrefix("> ") ? 2 : 1
                let delimRange = NSRange(location: range.location + searchStart, length: prefixLen)
                if NSMaxRange(delimRange) <= NSMaxRange(range) {
                    collectedDelimiterRanges.append(delimRange)
                }
            }
            searchStart += line.count + 1 // +1 for newline
        }

        descendInto(blockQuote)
    }

    // MARK: - Link

    mutating func visitLink(_ link: Link) {
        guard let range = resolveRange(link) else {
            descendInto(link)
            return
        }

        textStorage.addAttributes([
            .foregroundColor: config.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: range)

        // Collect the URL portion as delimiters: `[text](url)` — `[`, `](url)`
        let linkText = (string as NSString).substring(with: range)
        if let closeBracket = linkText.range(of: "](") {
            let prefixEnd = linkText.distance(from: linkText.startIndex, to: closeBracket.lowerBound)
            // Opening `[`
            collectedDelimiterRanges.append(NSRange(location: range.location, length: 1))
            // `](url)`
            let urlPartStart = range.location + prefixEnd
            let urlPartLen = range.length - prefixEnd
            if urlPartLen > 0 {
                let urlRange = NSRange(location: urlPartStart, length: urlPartLen)
                collectedDelimiterRanges.append(urlRange)
                textStorage.addAttribute(.font, value: config.codeFont, range: urlRange)
            }
        }

        descendInto(link)
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        listNestingDepth += 1
        applyListIndent(unorderedList, depth: listNestingDepth)
        descendInto(unorderedList)
        listNestingDepth -= 1
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        listNestingDepth += 1
        applyListIndent(orderedList, depth: listNestingDepth)
        descendInto(orderedList)
        listNestingDepth -= 1
    }

    mutating func visitListItem(_ listItem: ListItem) {
        guard let range = resolveRange(listItem) else {
            descendInto(listItem)
            return
        }

        let itemText = (string as NSString).substring(with: range)

        // Checkbox → tag for visual checkbox replacement
        if let checkbox = listItem.checkbox {
            let isChecked = checkbox == .checked
            let prefixLen = min(6, range.length) // "- [ ] " or "- [x] "
            let markerRange = NSRange(location: range.location, length: prefixLen)
            let type = isChecked ? "checkboxChecked" : "checkboxUnchecked"
            collectedMarkerRanges.append(MarkdownStyler.MarkerInfo(range: markerRange, type: type, nestingDepth: listNestingDepth))

            if isChecked, range.length > prefixLen {
                let contentRange = NSRange(
                    location: range.location + prefixLen,
                    length: range.length - prefixLen
                )
                textStorage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: config.quoteColor,
                ], range: contentRange)
            }
        } else {
            // Regular list item — detect marker prefix
            let trimmed = itemText.drop(while: { $0 == " " || $0 == "\t" })
            if let firstContentChar = trimmed.firstIndex(where: {
                $0 != "-" && $0 != "*" && $0 != "+"
                    && !$0.isNumber && $0 != "." && $0 != ")" && $0 != " "
            }) {
                let markerLen = itemText.distance(from: itemText.startIndex, to: firstContentChar)
                if markerLen > 0, markerLen <= range.length {
                    let markerRange = NSRange(location: range.location, length: markerLen)
                    let first = trimmed.first
                    if first == "-" || first == "*" || first == "+" {
                        // Bullet → tag for visual bullet dot replacement
                        collectedMarkerRanges.append(
                            MarkdownStyler.MarkerInfo(range: markerRange, type: "bullet", nestingDepth: listNestingDepth)
                        )
                    } else {
                        // Numbered list → tag for visual number replacement
                        // Extract the number from the marker text (e.g. "1. " → "1")
                        let numberStr = String(trimmed.prefix(while: \.isNumber))
                        let label = numberStr.isEmpty ? "1" : numberStr
                        collectedMarkerRanges.append(
                            MarkdownStyler.MarkerInfo(range: markerRange, type: "numberedList:\(label)", nestingDepth: listNestingDepth)
                        )
                    }
                }
            }
        }

        descendInto(listItem)
    }

    // MARK: - Table

    mutating func visitTable(_ table: Table) {
        guard let range = resolveRange(table) else {
            descendInto(table)
            return
        }

        let nsString = string as NSString
        let tableText = nsString.substring(with: range)
        let lines = tableText.components(separatedBy: "\n")

        // Count columns from the header row pipe characters
        let pipeCount = lines.first?.filter { $0 == "|" }.count ?? 0
        let columnCount = max(1, pipeCount - 1)

        // Apply body font + table column count to entire range (Notion uses proportional font)
        textStorage.addAttributes([
            .font: config.bodyFont,
            .foregroundColor: config.bodyColor,
            .tableColumnCount: columnCount,
        ], range: range)

        // Table row paragraph style with vertical padding for Notion-like cell height
        let tableParagraph = NSMutableParagraphStyle()
        tableParagraph.lineSpacing = 0
        tableParagraph.paragraphSpacingBefore = 6
        tableParagraph.paragraphSpacing = 6

        var lineStart = 0

        for (lineIndex, line) in lines.enumerated() {
            guard !line.isEmpty else {
                lineStart += line.utf16.count + 1
                continue
            }

            let lineRange = NSRange(location: range.location + lineStart, length: line.utf16.count)
            guard NSMaxRange(lineRange) <= NSMaxRange(range) else {
                lineStart += line.utf16.count + 1
                continue
            }

            if lineIndex == 1, line.contains("---") {
                // Separator line → collapse it visually
                collectedMarkerRanges.append(
                    MarkdownStyler.MarkerInfo(range: lineRange, type: "tableSeparator", nestingDepth: 0)
                )
            } else {
                // Apply cell padding paragraph style to visible rows
                textStorage.addAttribute(.paragraphStyle, value: tableParagraph, range: lineRange)

                // Header or body row
                if lineIndex == 0 {
                    // Semibold header and mark for background rendering
                    let headerFont = NSFont.systemFont(ofSize: config.bodyFont.pointSize, weight: .semibold)
                    textStorage.addAttribute(.font, value: headerFont, range: lineRange)
                    textStorage.addAttribute(.tableHeaderRow, value: true, range: lineRange)
                }

                // Mark pipe characters for hiding + grid line positioning
                let pipeUTF16: UInt16 = 0x7C
                for (i, char) in line.utf16.enumerated() where char == pipeUTF16 {
                    let pipeRange = NSRange(location: range.location + lineStart + i, length: 1)
                    if NSMaxRange(pipeRange) <= NSMaxRange(range) {
                        collectedMarkerRanges.append(
                            MarkdownStyler.MarkerInfo(range: pipeRange, type: "tablePipe", nestingDepth: 0)
                        )
                    }
                }
            }

            lineStart += line.utf16.count + 1
        }

        descendInto(table)
    }

    // MARK: - Thematic Break

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = resolveRange(thematicBreak) else { return }
        let dividerStyle = NSMutableParagraphStyle()
        dividerStyle.paragraphSpacingBefore = AppThemeConstants.dividerSpacingBefore
        dividerStyle.paragraphSpacing = AppThemeConstants.dividerSpacingAfter
        textStorage.addAttributes([
            .dividerRange: true,
            .paragraphStyle: dividerStyle,
        ], range: range)
        // Collect as marker so it gets hidden (visual line drawn by layout manager)
        collectedMarkerRanges.append(MarkdownStyler.MarkerInfo(range: range, type: "divider", nestingDepth: 0))
    }

    // MARK: - Helpers

    private func resolveRange(_ markup: any Markup) -> NSRange? {
        guard let sourceRange = markup.range else { return nil }
        return nsRange(from: sourceRange, in: string, lineOffsets: lineOffsets)
    }

    private mutating func collectDelimiters(in range: NSRange, prefixLen: Int, suffixLen: Int) {
        guard range.length >= prefixLen + suffixLen else { return }
        collectedDelimiterRanges.append(NSRange(location: range.location, length: prefixLen))
        collectedDelimiterRanges.append(NSRange(location: NSMaxRange(range) - suffixLen, length: suffixLen))
    }

    private func applyListIndent(_ markup: any Markup, depth: Int) {
        guard let range = resolveRange(markup) else { return }
        let indent = CGFloat(depth) * AppThemeConstants.listIndentPerLevel
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = AppThemeConstants.lineSpacingDefault
        paraStyle.headIndent = indent
        paraStyle.firstLineHeadIndent = indent - AppThemeConstants.listIndentPerLevel + AppThemeConstants.listFirstLineIndent
        paraStyle.paragraphSpacing = AppThemeConstants.listItemSpacing
        textStorage.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        textStorage.addAttribute(.listNestingDepth, value: depth, range: range)
    }
}
