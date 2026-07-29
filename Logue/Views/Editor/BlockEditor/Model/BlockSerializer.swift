import Foundation
import Markdown

// MARK: - BlockSerializer

/// Converts between markdown strings and Block arrays.
/// Uses swift-markdown (cmark-gfm) for parsing and a straightforward string builder for serialization.
enum BlockSerializer {
    // MARK: - Parse (Markdown → Blocks)

    static func parse(markdown: String) -> [Block] {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.emptyParagraph()]
        }

        // `$$` math fences are not CommonMark: cmark would parse them as a
        // paragraph and collapse the internal newlines into spaces, destroying
        // multi-line LaTeX. Split them out before handing the rest to cmark.
        var blocks: [Block] = []
        for segment in mathFenceSegments(in: markdown) {
            switch segment {
            case let .math(latex):
                blocks.append(.math(id: UUID(), latex: latex))
            case let .markdown(text):
                // Callouts get pulled out for the same reason as math fences: cmark reads one
                // as a block quote and folds its line breaks into spaces, so a multi-line
                // callout body could not be written back the way it arrived.
                for calloutSegment in calloutSegments(in: text) {
                    switch calloutSegment {
                    case let .callout(kind, title, body):
                        blocks.append(.callout(id: UUID(), kind: kind, title: title, body: body))
                    case let .markdown(plain):
                        blocks += parseMarkdownSegment(plain)
                    }
                }
            }
        }

        return blocks.isEmpty ? [.emptyParagraph()] : blocks
    }

    private static func parseMarkdownSegment(_ markdown: String) -> [Block] {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var blocks: [Block] = []

        for child in document.children {
            if let block = parseNode(child, source: markdown) {
                blocks.append(block)
            }
        }

        return blocks
    }

    // MARK: - Math Fence Splitting

    private enum MarkdownSegment {
        case markdown(String)
        case math(String)
    }

    private static let mathFence = "$$"

    /// Splits `markdown` into alternating plain-markdown and `$$`-fenced math runs,
    /// preserving document order. An unterminated fence is treated as ordinary
    /// markdown so malformed input never silently swallows the rest of the document.
    private static func mathFenceSegments(in markdown: String) -> [MarkdownSegment] {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == mathFence }) else {
            return [.markdown(markdown)]
        }

        var segments: [MarkdownSegment] = []
        var pending: [String] = []
        var mathLines: [String] = []
        var insideMath = false

        for line in lines {
            let isFence = line.trimmingCharacters(in: .whitespaces) == mathFence

            if isFence, !insideMath {
                if !pending.isEmpty {
                    segments.append(.markdown(pending.joined(separator: "\n")))
                    pending = []
                }
                insideMath = true
            } else if isFence, insideMath {
                segments.append(.math(mathLines.joined(separator: "\n")))
                mathLines = []
                insideMath = false
            } else if insideMath {
                mathLines.append(line)
            } else {
                pending.append(line)
            }
        }

        // Unterminated fence: restore the opening fence and its contents verbatim.
        if insideMath {
            pending.append(mathFence)
            pending += mathLines
        }
        if !pending.isEmpty {
            segments.append(.markdown(pending.joined(separator: "\n")))
        }

        return segments
    }

    // MARK: - Callout Splitting

    private enum CalloutSegment {
        case markdown(String)
        case callout(kind: CalloutKind, title: String, body: String)
    }

    /// Splits `markdown` into alternating plain-markdown runs and callout blocks.
    ///
    /// A callout is a block quote whose first line is `> [!TYPE]`, optionally followed by a
    /// title on the same line. It runs until the first line that is not part of the quote.
    /// Anything that is not one of the five recognised types — `> [!BANANA]`, or a plain
    /// `> quote` — is left in the markdown run untouched, so cmark parses it as the block
    /// quote it is.
    private static func calloutSegments(in markdown: String) -> [CalloutSegment] {
        guard markdown.contains("[!") else { return [.markdown(markdown)] }

        let lines = markdown.components(separatedBy: "\n")
        var segments: [CalloutSegment] = []
        var pending: [String] = []
        var index = 0

        while index < lines.count {
            guard let header = calloutHeader(in: lines[index]) else {
                pending.append(lines[index])
                index += 1
                continue
            }

            // Body lines are the quote lines that follow, stopping at the first line that is
            // not quoted — a blank line ends the quote in CommonMark, and a non-quote line
            // starts a new block.
            var bodyLines: [String] = []
            var cursor = index + 1
            while cursor < lines.count, let content = quotedContent(of: lines[cursor]) {
                bodyLines.append(content)
                cursor += 1
            }

            if !pending.isEmpty {
                segments.append(.markdown(pending.joined(separator: "\n")))
                pending = []
            }
            segments.append(.callout(
                kind: header.kind,
                title: header.title,
                body: bodyLines.joined(separator: "\n")
            ))
            index = cursor
        }

        if !pending.isEmpty {
            segments.append(.markdown(pending.joined(separator: "\n")))
        }

        return segments
    }

    /// Reads `> [!TYPE] optional title`, or `nil` when the line is not a callout header.
    private static func calloutHeader(in line: String) -> (kind: CalloutKind, title: String)? {
        guard let content = quotedContent(of: line) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), let closing = trimmed.firstIndex(of: "]") else { return nil }

        let marker = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2) ..< closing])
        guard let kind = CalloutKind(marker: marker) else { return nil }

        let title = trimmed[trimmed.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        return (kind, title)
    }

    /// The content of a quote line with its `>` marker removed, or `nil` if it is not one.
    ///
    /// Exactly one following space is dropped, because that space is the marker's separator
    /// rather than the author's indentation — dropping all leading whitespace would flatten a
    /// deliberately indented body line and break the round-trip.
    private static func quotedContent(of line: String) -> String? {
        guard let markerRange = line.range(of: ">"),
              line[line.startIndex ..< markerRange.lowerBound].allSatisfy(\.isWhitespace)
        else { return nil }

        let rest = line[markerRange.upperBound...]
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : String(rest)
    }

    // MARK: - Serialize (Blocks → Markdown)

    static func serialize(blocks: [Block]) -> String {
        blocks.map { serializeBlock($0) }.joined(separator: "\n\n")
    }

    // MARK: - Parse Helpers

    private static func parseNode(_ node: any Markup, source: String) -> Block? {
        switch node {
        case let heading as Heading:
            return parseHeading(heading, source: source)

        case let paragraph as Paragraph:
            return parseParagraph(paragraph, source: source)

        case let unorderedList as UnorderedList:
            return parseUnorderedList(unorderedList, source: source)

        case let orderedList as OrderedList:
            return parseOrderedList(orderedList, source: source)

        case let blockQuote as BlockQuote:
            return parseBlockQuote(blockQuote, source: source)

        case let codeBlock as CodeBlock:
            return parseCodeBlock(codeBlock)

        case is ThematicBreak:
            return .divider(id: UUID())

        case let table as Table:
            return parseTable(table, source: source)

        default:
            // Fallback: extract raw text as paragraph
            let text = extractPlainText(from: node, source: source)
            if !text.isEmpty {
                return .paragraph(id: UUID(), text: text)
            }
            return nil
        }
    }

    private static func parseHeading(_ heading: Heading, source: String) -> Block {
        let text = extractInlineText(from: heading, source: source)
        let level = max(1, min(heading.level, 6))
        return .heading(id: UUID(), level: level, text: text)
    }

    private static func parseParagraph(_ paragraph: Paragraph, source: String) -> Block {
        var text = extractInlineText(from: paragraph, source: source)
        // Strip &nbsp; placeholder used to preserve empty paragraphs in markdown
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "&nbsp;" || trimmed == "\u{00A0}" {
            text = ""
        }
        return .paragraph(id: UUID(), text: text)
    }

    private static func parseUnorderedList(_ list: UnorderedList, source: String) -> Block {
        // Detect if this is a checkbox/task list
        var hasCheckboxes = false
        for item in list.children.compactMap({ $0 as? Markdown.ListItem }) {
            // Check swift-markdown's checkbox property first
            if item.checkbox != nil {
                hasCheckboxes = true
                break
            }
            // Fallback: check text prefix (some swift-markdown versions don't populate checkbox)
            let itemText = extractInlineText(from: item, source: source)
            if itemText.hasPrefix("[ ] ") || itemText.hasPrefix("[x] ") || itemText.hasPrefix("[X] ") {
                hasCheckboxes = true
                break
            }
        }

        if hasCheckboxes {
            return parseCheckboxList(list, source: source)
        }

        var items: [BlockListItem] = []
        parseListItems(from: list, source: source, depth: 0, into: &items)
        return .bulletList(id: UUID(), items: items.isEmpty ? [BlockListItem()] : items)
    }

    private static func parseCheckboxList(_ list: UnorderedList, source: String) -> Block {
        var items: [CheckboxItem] = []
        parseCheckboxItems(from: list, source: source, depth: 0, into: &items)
        return .checkboxList(id: UUID(), items: items.isEmpty ? [CheckboxItem()] : items)
    }

    private static func parseOrderedList(_ list: OrderedList, source: String) -> Block {
        var items: [BlockListItem] = []
        parseListItems(from: list, source: source, depth: 0, into: &items)
        return .numberedList(id: UUID(), items: items.isEmpty ? [BlockListItem()] : items)
    }

    private static func parseListItems(from node: any Markup, source: String, depth: Int, into items: inout [BlockListItem]) {
        for child in node.children {
            if let markdownItem = child as? Markdown.ListItem {
                let text = extractInlineText(from: markdownItem, source: source)
                items.append(BlockListItem(text: text, indent: depth))

                // Check for nested lists inside this list item
                for subchild in markdownItem.children {
                    if subchild is UnorderedList || subchild is OrderedList {
                        parseListItems(from: subchild, source: source, depth: depth + 1, into: &items)
                    }
                }
            } else if child is UnorderedList || child is OrderedList {
                parseListItems(from: child, source: source, depth: depth + 1, into: &items)
            }
        }
    }

    private static func parseCheckboxItems(
        from node: any Markup, source: String, depth: Int, into items: inout [CheckboxItem]
    ) {
        for child in node.children {
            if let markdownItem = child as? Markdown.ListItem {
                var text = extractInlineText(from: markdownItem, source: source)
                var isChecked = false

                if let checkbox = markdownItem.checkbox {
                    // swift-markdown parsed the checkbox — text won't contain [ ] prefix
                    isChecked = checkbox == .checked
                } else {
                    // Fallback: strip [ ] / [x] prefix from text
                    if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                        isChecked = true
                        text = String(text.dropFirst(4))
                    } else if text.hasPrefix("[ ] ") {
                        isChecked = false
                        text = String(text.dropFirst(4))
                    }
                }

                items.append(CheckboxItem(text: text, isChecked: isChecked, indent: depth))

                for subchild in markdownItem.children where subchild is UnorderedList {
                    parseCheckboxItems(from: subchild, source: source, depth: depth + 1, into: &items)
                }
            }
        }
    }

    private static func parseBlockQuote(_ blockQuote: BlockQuote, source: String) -> Block {
        // Extract all text content from the block quote, preserving inner paragraphs
        var lines: [String] = []
        for child in blockQuote.children {
            let text = extractInlineText(from: child, source: source)
            lines.append(text)
        }
        return .blockQuote(id: UUID(), text: lines.joined(separator: "\n"))
    }

    private static func parseCodeBlock(_ codeBlock: CodeBlock) -> Block {
        let language = codeBlock.language ?? ""
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code
        // A `mermaid`-tagged fence is a diagram, not source code to syntax-highlight.
        if language.lowercased() == Self.mermaidLanguage {
            return .mermaid(id: UUID(), source: code)
        }
        return .codeBlock(id: UUID(), language: language, code: code)
    }

    private static func parseTable(_ table: Table, source: String) -> Block {
        var rows: [[String]] = []

        // Header row
        if let head = table.head as? Table.Head {
            var headerCells: [String] = []
            for cell in head.cells {
                headerCells.append(extractInlineText(from: cell, source: source))
            }
            rows.append(headerCells)
        }

        // Body rows
        if let body = table.body as? Table.Body {
            for row in body.rows {
                var cellTexts: [String] = []
                for cell in row.cells {
                    cellTexts.append(extractInlineText(from: cell, source: source))
                }
                rows.append(cellTexts)
            }
        }

        let colCount = rows.first?.count ?? 3
        let tableData = TableBlockData(columns: colCount, rowCount: rows.count)
        tableData.rows = rows.map { row in
            var padded = row
            while padded.count < colCount {
                padded.append("")
            }
            return Array(padded.prefix(colCount))
        }

        return .table(id: UUID(), data: tableData)
    }

    // MARK: - Text Extraction

    /// Extracts the raw inline text content from a markup node, preserving inline markdown formatting.
    private static func extractInlineText(from node: any Markup, source: String) -> String {
        // For leaf nodes with direct text, collect inline children
        var parts: [String] = []
        collectInlineText(from: node, into: &parts)
        let joined = parts.joined()
        return joined.trimmingCharacters(in: .newlines)
    }

    private static func collectInlineText(from node: any Markup, into parts: inout [String]) {
        for child in node.children {
            if let text = child as? Markdown.Text {
                parts.append(text.string)
            } else if let code = child as? InlineCode {
                parts.append("`\(code.code)`")
            } else if let strong = child as? Strong {
                parts.append("**")
                collectInlineText(from: strong, into: &parts)
                parts.append("**")
            } else if let emphasis = child as? Emphasis {
                parts.append("*")
                collectInlineText(from: emphasis, into: &parts)
                parts.append("*")
            } else if let strikethrough = child as? Strikethrough {
                parts.append("~~")
                collectInlineText(from: strikethrough, into: &parts)
                parts.append("~~")
            } else if let link = child as? Link {
                parts.append("[")
                collectInlineText(from: link, into: &parts)
                parts.append("](\(link.destination ?? ""))")
            } else if let image = child as? Image {
                parts.append("![\(image.plainText)](\(image.source ?? ""))")
            } else if let html = child as? InlineHTML {
                parts.append(html.rawHTML)
            } else if child is SoftBreak {
                parts.append(" ")
            } else if child is LineBreak {
                parts.append("\n")
            } else if child is UnorderedList || child is OrderedList || child is Markdown.ListItem {
                // Skip list structures — handled separately by parseListItems/parseCheckboxItems
                continue
            } else if child is Paragraph {
                // Nested paragraph inside list item — extract its inline content
                collectInlineText(from: child, into: &parts)
            } else {
                // Fallback: recurse into children
                collectInlineText(from: child, into: &parts)
            }
        }
    }

    private static func extractPlainText(from node: any Markup, source: String) -> String {
        var visitor = PlainTextVisitor()
        visitor.visit(node)
        return visitor.result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Serialize Helpers

    static func serializeBlock(_ block: Block) -> String {
        switch block {
        case let .paragraph(_, text):
            // Empty paragraphs need a placeholder to survive markdown round-trip
            // (consecutive \n\n are treated as a single block separator by parsers)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "&nbsp;" : text

        case let .heading(_, level, text):
            let prefix = String(repeating: "#", count: level)
            return "\(prefix) \(text)"

        case let .bulletList(_, items):
            return serializeBulletList(items)

        case let .numberedList(_, items):
            return serializeNumberedList(items)

        case let .checkboxList(_, items):
            return serializeCheckboxList(items)

        case let .blockQuote(_, text):
            return text.components(separatedBy: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")

        case let .codeBlock(_, language, code):
            let fence = "```"
            return "\(fence)\(language)\n\(code)\n\(fence)"

        case let .table(_, data):
            return data.toMarkdown()

        case .divider:
            return "---"

        case let .mermaid(_, source):
            return "```\(Self.mermaidLanguage)\n\(source)\n```"

        case let .callout(_, kind, title, body):
            return serializeCallout(kind: kind, title: title, body: body)

        case let .math(_, latex):
            return "\(mathFence)\n\(latex)\n\(mathFence)"
        }
    }

    /// Writes a callout back as `> [!TYPE] title` plus quoted body lines.
    ///
    /// An empty body line serializes as a bare `>` rather than `"> "`, which is what it was
    /// read from — a trailing space there is the one thing that would stop the round-trip
    /// being byte-exact.
    private static func serializeCallout(kind: CalloutKind, title: String, body: String) -> String {
        var lines = ["> [!\(kind.rawValue)]" + (title.isEmpty ? "" : " \(title)")]
        // A callout with no body is a single header line, not a header plus an empty quote.
        if !body.isEmpty {
            lines += body.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    static let mermaidLanguage = "mermaid"

    private static func serializeBulletList(_ items: [BlockListItem]) -> String {
        items.map { item in
            let indent = String(repeating: "  ", count: item.indent)
            return "\(indent)- \(item.text)"
        }.joined(separator: "\n")
    }

    private static func serializeNumberedList(_ items: [BlockListItem]) -> String {
        var counters: [Int: Int] = [:] // indent level -> current number
        return items.map { item in
            let indent = String(repeating: "  ", count: item.indent)
            let number = (counters[item.indent] ?? 0) + 1
            counters[item.indent] = number
            // Reset deeper level counters when we're at a shallower level
            for key in counters.keys where key > item.indent {
                counters[key] = 0
            }
            return "\(indent)\(number). \(item.text)"
        }.joined(separator: "\n")
    }

    private static func serializeCheckboxList(_ items: [CheckboxItem]) -> String {
        items.map { item in
            let indent = String(repeating: "  ", count: item.indent)
            let check = item.isChecked ? "x" : " "
            return "\(indent)- [\(check)] \(item.text)"
        }.joined(separator: "\n")
    }
}

// MARK: - PlainTextVisitor

private struct PlainTextVisitor: MarkupWalker {
    var result = ""

    mutating func visitText(_ text: Markdown.Text) {
        result += text.string
    }

    mutating func visitSoftBreak(_: SoftBreak) {
        result += " "
    }

    mutating func visitLineBreak(_: LineBreak) {
        result += "\n"
    }
}
