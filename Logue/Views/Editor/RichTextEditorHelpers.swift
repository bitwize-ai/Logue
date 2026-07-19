import AppKit
import SwiftUI

// MARK: - Menu Icon Helper

private extension NSImage {
    /// Creates a symbol image sized for menus using the shared `menuIconPointSize` token.
    static func menuIcon(systemName: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: systemName, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: AppThemeConstants.menuIconPointSize, weight: .regular))
    }
}

// MARK: - BlockType

/// Block types available in the + (add block) and "Turn into" menus.
enum BlockType: String, CaseIterable {
    case text
    case heading1, heading2, heading3
    case bulletList, numberedList, todoList
    case quote, divider, codeBlock, table

    var displayName: String {
        switch self {
        case .text: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .todoList: "To-Do List"
        case .quote: "Quote"
        case .divider: "Divider"
        case .codeBlock: "Code Block"
        case .table: "Table"
        }
    }

    var iconName: String {
        switch self {
        case .text: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .todoList: "checklist"
        case .quote: "text.quote"
        case .divider: "minus"
        case .codeBlock: "chevron.left.forwardslash.chevron.right"
        case .table: "tablecells"
        }
    }

    var description: String {
        switch self {
        case .text: "Plain text paragraph"
        case .heading1: "Large section heading"
        case .heading2: "Medium section heading"
        case .heading3: "Small section heading"
        case .bulletList: "Unordered list item"
        case .numberedList: "Ordered list item"
        case .todoList: "Checkbox item"
        case .quote: "Highlighted quote block"
        case .divider: "Horizontal separator line"
        case .codeBlock: "Syntax-highlighted code"
        case .table: "Grid of rows and columns"
        }
    }

    enum Category: String, CaseIterable {
        case text = "Text"
        case lists = "Lists"
        case advanced = "Advanced"
    }

    var category: Category {
        switch self {
        case .text, .heading1, .heading2, .heading3: .text
        case .bulletList, .numberedList, .todoList: .lists
        case .quote, .divider, .codeBlock, .table: .advanced
        }
    }

    /// Block types grouped by category, preserving order.
    static var groupedByCategory: [(category: Category, types: [BlockType])] {
        Category.allCases.compactMap { cat in
            let types = allCases.filter { $0.category == cat }
            return types.isEmpty ? nil : (cat, types)
        }
    }

    var markdownPrefix: String {
        switch self {
        case .text: ""
        case .heading1: "# "
        case .heading2: "## "
        case .heading3: "### "
        case .bulletList: "- "
        case .numberedList: "1. "
        case .todoList: "- [ ] "
        case .quote: "> "
        case .divider: "---"
        case .codeBlock: "```"
        case .table: ""
        }
    }

    /// Block types that can be used in "Turn into" (excludes divider/codeBlock/table).
    static var turnIntoTypes: [BlockType] {
        [.text, .heading1, .heading2, .heading3, .bulletList, .numberedList, .todoList, .quote]
    }

    /// Creates a new empty block of this type.
    func makeEmptyBlock() -> Block {
        switch self {
        case .text: .emptyParagraph()
        case .heading1: .emptyHeading(level: 1)
        case .heading2: .emptyHeading(level: 2)
        case .heading3: .emptyHeading(level: 3)
        case .bulletList: .emptyBulletList()
        case .numberedList: .emptyNumberedList()
        case .todoList: .emptyCheckboxList()
        case .quote: .emptyBlockQuote()
        case .divider: .newDivider()
        case .codeBlock: .emptyCodeBlock()
        case .table: .emptyTable()
        }
    }
}

// MARK: - Add Block Menu (+)

extension WritingNSTextView {
    @objc
    func showAddBlockMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let groups: [[BlockType]] = [
            [.text, .heading1, .heading2, .heading3],
            [.bulletList, .numberedList, .todoList],
            [.quote, .divider, .codeBlock, .table],
        ]

        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 {
                menu.addItem(.separator())
            }
            for blockType in group {
                let item = NSMenuItem(
                    title: blockType.displayName,
                    action: #selector(handleAddBlock(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.isEnabled = true
                item.representedObject = blockType.rawValue
                item.image = .menuIcon(systemName: blockType.iconName, description: blockType.displayName)
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: menu.items.first, at: addBlockButton.frame.origin, in: self)
    }

    @objc
    private func handleAddBlock(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let blockType = BlockType(rawValue: rawValue)
        else { return }
        insertBlock(blockType, at: hoveredCharIndex)
    }

    /// Inserts a new block below the line at `charIndex`.
    func insertBlock(_ blockType: BlockType, at charIndex: Int) {
        let nsString = string as NSString
        let lr = safeLineRange(at: charIndex)
        let insertAt = min(NSMaxRange(lr), nsString.length)
        let needsNewline = insertAt > 0 && !nsString.substring(with: NSRange(location: insertAt - 1, length: 1)).hasSuffix("\n")

        switch blockType {
        case .divider:
            let text = (needsNewline ? "\n" : "") + "---\n"
            replaceRange(NSRange(location: insertAt, length: 0), with: text)
            let caretPos = insertAt + text.utf16.count
            setSelectedRange(NSRange(location: caretPos, length: 0))

        case .codeBlock:
            let text = (needsNewline ? "\n" : "") + "```\n\n```\n"
            replaceRange(NSRange(location: insertAt, length: 0), with: text)
            // Place cursor inside the code block (after first ```)
            let offset = (needsNewline ? 1 : 0) + 4 // "```\n" = 4
            setSelectedRange(NSRange(location: insertAt + offset, length: 0))

        case .table:
            insertTableBlock(at: charIndex)

        default:
            let prefix = blockType.markdownPrefix
            let text = (needsNewline ? "\n" : "") + prefix
            replaceRange(NSRange(location: insertAt, length: 0), with: text)
            let caretPos = insertAt + text.utf16.count
            setSelectedRange(NSRange(location: caretPos, length: 0))
        }
    }
}

// MARK: - Block Options Menu (⋮⋮)

extension WritingNSTextView {
    @objc
    func showBlockOptionsMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Turn into submenu
        let turnIntoItem = NSMenuItem(title: "Turn into", action: nil, keyEquivalent: "")
        turnIntoItem.image = .menuIcon(systemName: "arrow.triangle.swap", description: "Turn into")
        let turnIntoMenu = NSMenu()
        for blockType in BlockType.turnIntoTypes {
            let item = NSMenuItem(
                title: blockType.displayName,
                action: #selector(handleTurnInto(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.representedObject = blockType.rawValue
            item.image = NSImage(systemSymbolName: blockType.iconName, accessibilityDescription: blockType.displayName)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            turnIntoMenu.addItem(item)
        }
        turnIntoItem.submenu = turnIntoMenu
        menu.addItem(turnIntoItem)

        menu.addItem(.separator())

        // Move
        let upItem = NSMenuItem(title: "Move Up", action: #selector(moveLineUp), keyEquivalent: "")
        upItem.target = self; upItem.isEnabled = true
        upItem.image = .menuIcon(systemName: "arrow.up", description: "Move Up")
        menu.addItem(upItem)

        let downItem = NSMenuItem(title: "Move Down", action: #selector(moveLineDown), keyEquivalent: "")
        downItem.target = self; downItem.isEnabled = true
        downItem.image = .menuIcon(systemName: "arrow.down", description: "Move Down")
        menu.addItem(downItem)

        menu.addItem(.separator())

        // Duplicate
        let dupItem = NSMenuItem(title: "Duplicate", action: #selector(duplicateLine), keyEquivalent: "")
        dupItem.target = self; dupItem.isEnabled = true
        dupItem.image = .menuIcon(systemName: "plus.square.on.square", description: "Duplicate")
        menu.addItem(dupItem)

        // Copy
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyLine), keyEquivalent: "")
        copyItem.target = self; copyItem.isEnabled = true
        copyItem.image = .menuIcon(systemName: "doc.on.doc", description: "Copy")
        menu.addItem(copyItem)

        // Delete
        let delItem = NSMenuItem(title: "Delete", action: #selector(deleteLine), keyEquivalent: "")
        delItem.target = self; delItem.isEnabled = true
        delItem.image = .menuIcon(systemName: "trash", description: "Delete")
        menu.addItem(delItem)

        menu.popUp(positioning: menu.items.first, at: blockOptionsButton.frame.origin, in: self)
    }

    @objc
    private func handleTurnInto(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let blockType = BlockType(rawValue: rawValue)
        else { return }
        setMarkdownLinePrefix(blockType.markdownPrefix, at: hoveredCharIndex)
    }
}

// MARK: - Line Operations

extension WritingNSTextView {
    func safeLineRange(at charIndex: Int) -> NSRange {
        let nsString = string as NSString
        guard nsString.length > 0 else { return NSRange(location: 0, length: 0) }
        let safe = min(max(0, charIndex), nsString.length - 1)
        return nsString.lineRange(for: NSRange(location: safe, length: 0))
    }

    func replaceRange(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
    }

    @objc
    func moveLineUp() {
        let nsString = string as NSString
        let lr = safeLineRange(at: hoveredCharIndex)
        guard lr.location > 0 else { return }
        let prevLR = nsString.lineRange(for: NSRange(location: lr.location - 1, length: 0))
        let lineText = nsString.substring(with: lr)
        let prevText = nsString.substring(with: prevLR)
        let swapRange = NSRange(location: prevLR.location, length: prevLR.length + lr.length)
        replaceRange(swapRange, with: lineText + prevText)
        setSelectedRange(NSRange(location: prevLR.location, length: 0))
    }

    @objc
    func moveLineDown() {
        let nsString = string as NSString
        let lr = safeLineRange(at: hoveredCharIndex)
        let nextStart = NSMaxRange(lr)
        guard nextStart < nsString.length else { return }
        let nextLR = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
        let lineText = nsString.substring(with: lr)
        let nextText = nsString.substring(with: nextLR)
        let swapRange = NSRange(location: lr.location, length: lr.length + nextLR.length)
        replaceRange(swapRange, with: nextText + lineText)
        setSelectedRange(NSRange(location: lr.location + nextLR.length, length: 0))
    }

    @objc
    func insertLineAbove() {
        let lr = safeLineRange(at: hoveredCharIndex)
        replaceRange(NSRange(location: lr.location, length: 0), with: "\n")
        setSelectedRange(NSRange(location: lr.location, length: 0))
    }

    @objc
    func insertLineBelow() {
        let nsString = string as NSString
        let lr = safeLineRange(at: hoveredCharIndex)
        let insertAt = min(NSMaxRange(lr), nsString.length)
        replaceRange(NSRange(location: insertAt, length: 0), with: "\n")
        setSelectedRange(NSRange(location: insertAt + 1, length: 0))
    }

    @objc
    func duplicateLine() {
        let nsString = string as NSString
        let lr = safeLineRange(at: hoveredCharIndex)
        let lineText = nsString.substring(with: lr)
        let insertAt = min(NSMaxRange(lr), nsString.length)
        let toInsert = lineText.hasSuffix("\n") ? lineText : "\n" + lineText
        replaceRange(NSRange(location: insertAt, length: 0), with: toInsert)
    }

    @objc
    func deleteLine() {
        replaceRange(safeLineRange(at: hoveredCharIndex), with: "")
    }

    @objc
    func copyLine() {
        let nsString = string as NSString
        let lr = safeLineRange(at: hoveredCharIndex)
        let lineText = nsString.substring(with: lr)
        let trimmed = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }
}

// MARK: - Markdown Line Prefix

extension WritingNSTextView {
    /// All known markdown line prefixes, ordered longest-first for greedy matching.
    private static let knownPrefixes = [
        "### ", "## ", "# ",
        "- [x] ", "- [ ] ",
        "- ", "* ", "+ ",
        "> ",
    ]

    /// Regex to match numbered list prefixes like `1. `, `12) `.
    private static let numberedListRegex = try? NSRegularExpression(pattern: #"^\d+[.)]\s+"#)

    /// Replaces any existing markdown prefix on the line with the new one.
    /// Pass `""` to remove the prefix (Normal paragraph).
    func setMarkdownLinePrefix(_ newPrefix: String, at charIndex: Int) {
        let lr = safeLineRange(at: charIndex)
        guard lr.length > 0 else { return }
        let nsString = string as NSString
        let lineText = nsString.substring(with: lr)

        // Preserve leading whitespace (nesting indentation)
        let leadingSpaces = String(lineText.prefix(while: { $0 == " " }))
        var strippedLine = String(lineText.dropFirst(leadingSpaces.count))

        // Strip known static prefixes
        if let matched = Self.knownPrefixes.first(where: { strippedLine.hasPrefix($0) }) {
            strippedLine = String(strippedLine.dropFirst(matched.count))
        } else {
            // Strip numbered list prefix (e.g., "1. ", "12) ")
            let lineNS = strippedLine as NSString
            let lineRange = NSRange(location: 0, length: lineNS.length)
            if let match = Self.numberedListRegex?.firstMatch(in: strippedLine, range: lineRange) {
                strippedLine = String(strippedLine.dropFirst(match.range.length))
            }
        }

        let newLine = leadingSpaces + newPrefix + strippedLine
        guard newLine != lineText else { return }
        replaceRange(lr, with: newLine)

        // Place caret after the new prefix (including leading spaces)
        let caretPos = lr.location + leadingSpaces.utf16.count + newPrefix.utf16.count
        setSelectedRange(NSRange(location: caretPos, length: 0))
    }
}

// MARK: - SelectionToolbarView

struct SelectionToolbarView: View {
    let formattingState: FormattingState
    let onAction: (FormattingAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            FormatButton(symbol: "bold", tooltip: "Bold", isActive: formattingState.isBold, action: { onAction(.bold) })
            FormatButton(symbol: "italic", tooltip: "Italic", isActive: formattingState.isItalic, action: { onAction(.italic) })
            FormatButton(symbol: "underline", tooltip: "Underline", isActive: formattingState.isUnderlined, action: { onAction(.underline) })
            toolbarDivider
            FormatButton(
                symbol: "strikethrough",
                tooltip: "Strikethrough",
                isActive: formattingState.isStrikethrough,
                action: { onAction(.strikethrough) }
            )
            FormatButton(symbol: "chevron.left.forwardslash.chevron.right", tooltip: "Inline Code", action: { onAction(.inlineCode) })
            toolbarDivider
            FormatButton(symbol: "link", tooltip: "Link", action: { onAction(.link) })
            FormatButton(symbol: "doc.on.doc", tooltip: "Copy", action: { onAction(.copySelection) })
            toolbarDivider
            rewriteButton
            askAIButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .fixedSize()
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(AppThemeConstants.panelShadowOpacity),
            radius: AppThemeConstants.panelShadowRadius,
            x: 0,
            y: AppThemeConstants.panelShadowY
        )
        .padding(10)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 3)
    }

    private var askAIButton: some View {
        Button { onAction(.askAI) } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Ask AI")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                AppThemeConstants.brandPrimary.opacity(AppThemeConstants.activeOpacity),
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
            )
            .foregroundStyle(AppThemeConstants.brandPrimary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .help("Ask AI about selection")
    }

    /// Triggers in-place rewrite of the selection with a user-provided instruction.
    /// Distinct from "Ask AI" which opens a side-panel chat — Rewrite edits the
    /// selected text directly with an accept/reject diff, matching the Granola-style
    /// inline editing pattern.
    private var rewriteButton: some View {
        Button { onAction(.rewrite) } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                Text("Rewrite")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                AppThemeConstants.accent.opacity(AppThemeConstants.activeOpacity),
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
            )
            .foregroundStyle(AppThemeConstants.accent)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .help("Rewrite selection with AI (⌘⇧E)")
    }
}

// MARK: - FormatButton

struct FormatButton: View {
    let symbol: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(isActive ? AppThemeConstants.brandPrimary : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                        .fill(isActive ? AppThemeConstants.brandPrimary
                            .opacity(0.18) : (isHovered ? Color.primary.opacity(AppThemeConstants.opacityLight) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}
