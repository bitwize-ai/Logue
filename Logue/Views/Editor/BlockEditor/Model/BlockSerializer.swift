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

        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var blocks: [Block] = []

        for child in document.children {
            if let block = parseNode(child, source: markdown) {
                blocks.append(block)
            }
        }

        return blocks.isEmpty ? [.emptyParagraph()] : blocks
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
        }
    }

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
