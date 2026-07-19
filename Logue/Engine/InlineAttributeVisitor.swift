import AppKit
import Markdown

// MARK: - InlineAttributeVisitor

/// Lightweight AST visitor that only handles inline formatting (bold, italic, strikethrough, code, links).
/// Used by `restyleInline()` for per-block editing where block-level elements are already handled
/// by the block model (headings have no `#` prefix, code blocks are separate, etc.).
struct InlineAttributeVisitor: MarkupWalker {
    let textStorage: NSTextStorage
    let string: String
    let lineOffsets: [Int]
    let config: MarkdownStyler.StyleConfig

    var isInsideStrong = false
    var isInsideEmphasis = false
    var collectedDelimiterRanges: [NSRange] = []

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

        collectDelimiters(in: range, prefixLen: 1, suffixLen: 1)
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

        let linkText = (string as NSString).substring(with: range)
        if let closeBracket = linkText.range(of: "](") {
            let prefixEnd = linkText.distance(from: linkText.startIndex, to: closeBracket.lowerBound)
            collectedDelimiterRanges.append(NSRange(location: range.location, length: 1))
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
}
