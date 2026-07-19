import SwiftUI

// MARK: - Block Operations, Menus & Bindings

extension BlockRowView {
    // MARK: - Search Highlights

    /// Returns search highlights for a block-level text (paragraph, heading, blockquote, code).
    func blockSearchHighlights() -> [(range: NSRange, isCurrent: Bool)] {
        searchMatches.filter { $0.itemID == nil }.map { match in
            (range: match.range, isCurrent: match.id == currentSearchMatchID)
        }
    }

    /// Returns search highlights for a specific list item.
    func itemSearchHighlights(itemID: UUID) -> [(range: NSRange, isCurrent: Bool)] {
        searchMatches.filter { $0.itemID == itemID }.map { match in
            (range: match.range, isCurrent: match.id == currentSearchMatchID)
        }
    }

    // MARK: - Spacing Constants

    var listMarkerSpacing: CGFloat {
        fontSize * 1
    }

    var listIndentWidth: CGFloat {
        fontSize * 1.75
    }

    var blockquoteBarWidth: CGFloat {
        max(3, fontSize * 0.2)
    }

    // MARK: - Block Operations

    func splitBlock(id: BlockID, at offset: Int) {
        if let newID = document.splitBlock(id: id, atOffset: offset) {
            focusedBlockID = newID
            pendingCursorOffset = 0
        }
    }

    @discardableResult
    func mergeWithPrevious(id: BlockID) -> Bool {
        if let result = document.mergeWithPrevious(id: id) {
            focusedBlockID = result.blockID
            pendingCursorOffset = result.cursorOffset
            return true
        }
        return false
    }

    /// Handles multi-block markdown paste by parsing through BlockSerializer
    /// and inserting the resulting blocks after the current block.
    func handleMultiBlockPaste(blockID: BlockID, markdown: String) {
        let pastedBlocks = BlockSerializer.parse(markdown: markdown)
        guard !pastedBlocks.isEmpty else { return }

        // Insert all pasted blocks after the current block
        var insertAfterID = blockID
        for pastedBlock in pastedBlocks {
            document.insertBlock(pastedBlock, after: insertAfterID)
            insertAfterID = pastedBlock.id
        }

        // Focus the last inserted block
        focusedBlockID = insertAfterID
    }

    func focusPrevious(before id: BlockID, cursorXPosition: CGFloat? = nil) {
        guard let idx = document.index(of: id), idx > 0 else { return }
        let prevBlock = document.blocks[idx - 1]
        focusedBlockID = prevBlock.id
        pendingCursorXPosition = goalColumnX ?? cursorXPosition
        // Place cursor at end of previous block's text
        pendingCursorOffset = prevBlock.textContent?.count ?? 0
        switch prevBlock {
        case let .bulletList(_, items), let .numberedList(_, items):
            focusedItemID = items.last?.id
            pendingCursorOffset = items.last?.text.count ?? 0
        case let .checkboxList(_, items):
            focusedItemID = items.last?.id
            pendingCursorOffset = items.last?.text.count ?? 0
        default:
            focusedItemID = nil
        }
    }

    func focusNext(after id: BlockID, cursorXPosition: CGFloat? = nil) {
        guard let idx = document.index(of: id), idx + 1 < document.blocks.count else { return }
        let nextBlock = document.blocks[idx + 1]
        focusedBlockID = nextBlock.id
        pendingCursorXPosition = goalColumnX ?? cursorXPosition
        // Place cursor at start of next block
        pendingCursorOffset = 0
        switch nextBlock {
        case let .bulletList(_, items), let .numberedList(_, items):
            focusedItemID = items.first?.id
        case let .checkboxList(_, items):
            focusedItemID = items.first?.id
        default:
            focusedItemID = nil
        }
    }

    // MARK: - Slash Command

    /// Hidden anchor that presents a native NSMenu when the user types `/` at start of a paragraph.
    var slashCommandMenuAnchor: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: showSlashCommand) { _, show in
                guard show else { return }
                let currentResponder = NSApp.keyWindow?.firstResponder as? NSTextView
                DispatchQueue.main.async {
                    presentSlashMenu(textView: currentResponder)
                    showSlashCommand = false
                }
            }
    }

    func presentSlashMenu(textView: NSTextView?) {
        let blockID = block.id
        let doc = document
        let focusedBlockIDBinding = $focusedBlockID
        let focusedItemIDBinding = $focusedItemID
        let target = SlashMenuTarget { rawValue in
            guard let blockType = BlockType(rawValue: rawValue) else { return }
            let newBlock = blockType.makeEmptyBlock()
            doc.replaceBlock(id: blockID, with: newBlock)
            focusedBlockIDBinding.wrappedValue = newBlock.id
            focusedItemIDBinding.wrappedValue = newBlock.firstListItemID
        }
        slashTarget = target

        let menu = NSMenu(title: "Blocks")
        for group in BlockType.groupedByCategory {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let header = NSMenuItem(title: group.category.rawValue, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for blockType in group.types {
                let item = NSMenuItem(
                    title: blockType.displayName,
                    action: #selector(SlashMenuTarget.menuAction(_:)),
                    keyEquivalent: ""
                )
                item.image = NSImage(systemSymbolName: blockType.iconName, accessibilityDescription: blockType.displayName)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
                item.representedObject = blockType.rawValue
                item.target = target
                menu.addItem(item)
            }
        }

        // Present near the text cursor
        if let textView {
            let insertionPoint = textView.selectedRange().location
            let glyphRange = textView.layoutManager?.glyphRange(
                forCharacterRange: NSRange(location: insertionPoint, length: 0),
                actualCharacterRange: nil
            ) ?? NSRange(location: 0, length: 0)
            var rect = textView.layoutManager?.boundingRect(
                forGlyphRange: glyphRange,
                in: textView.textContainer ?? NSTextContainer()
            ) ?? .zero
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += rect.height + textView.textContainerInset.height + 4
            menu.popUp(positioning: nil, at: rect.origin, in: textView)
        } else if let window = NSApp.keyWindow, let contentView = window.contentView {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            menu.popUp(positioning: nil, at: contentView.convert(windowPoint, from: nil), in: contentView)
        }

        // popUp is synchronous — clean up the target now that the menu has dismissed
        slashTarget = nil
    }

    func focusBlock(_ block: Block) {
        focusedBlockID = block.id
        focusedItemID = block.firstListItemID
    }

    // MARK: - Shared Menu Items

    @ViewBuilder
    var turnIntoMenuItems: some View {
        if block.isTextBlock {
            Menu("Turn into") {
                Button("Text") { turnInto(.text) }
                Button("Heading 1") { turnInto(.heading1) }
                Button("Heading 2") { turnInto(.heading2) }
                Button("Heading 3") { turnInto(.heading3) }
                Button("Quote") { turnInto(.quote) }
                Button("Code Block") { turnInto(.codeBlock) }
            }
            Divider()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    var blockContextMenu: some View {
        turnIntoMenuItems

        Button("Duplicate") {
            let copy = duplicateBlock(block)
            document.insertBlock(copy, after: block.id)
            focusedBlockID = copy.id
        }

        Button("Delete", role: .destructive) {
            if let fallbackIdx = document.removeBlock(id: block.id) {
                focusedBlockID = document.blocks[fallbackIdx].id
            }
        }
    }

    func turnInto(_ blockType: BlockType) {
        let text = block.textContent ?? ""
        let newBlock: Block
        switch blockType {
        case .text:
            newBlock = .paragraph(id: block.id, text: text)
        case .heading1:
            newBlock = .heading(id: block.id, level: 1, text: text)
        case .heading2:
            newBlock = .heading(id: block.id, level: 2, text: text)
        case .heading3:
            newBlock = .heading(id: block.id, level: 3, text: text)
        case .quote:
            newBlock = .blockQuote(id: block.id, text: text)
        case .codeBlock:
            newBlock = .codeBlock(id: block.id, language: "", code: text)
        default:
            return
        }
        document.replaceBlock(id: block.id, with: newBlock)
    }

    func duplicateBlock(_ source: Block) -> Block {
        let newID = UUID()
        switch source {
        case let .paragraph(_, text):
            return .paragraph(id: newID, text: text)
        case let .heading(_, level, text):
            return .heading(id: newID, level: level, text: text)
        case let .bulletList(_, items):
            return .bulletList(id: newID, items: items.map { BlockListItem(text: $0.text, indent: $0.indent) })
        case let .numberedList(_, items):
            return .numberedList(id: newID, items: items.map { BlockListItem(text: $0.text, indent: $0.indent) })
        case let .checkboxList(_, items):
            return .checkboxList(id: newID, items: items.map {
                CheckboxItem(text: $0.text, isChecked: $0.isChecked, indent: $0.indent)
            })
        case let .blockQuote(_, text):
            return .blockQuote(id: newID, text: text)
        case let .codeBlock(_, lang, code):
            return .codeBlock(id: newID, language: lang, code: code)
        case let .table(_, data):
            let copy = TableBlockData(columns: data.columns, rowCount: data.rows.count)
            copy.rows = data.rows
            copy.columnWidths = data.columnWidths
            return .table(id: newID, data: copy)
        case .divider:
            return .divider(id: newID)
        }
    }

    // MARK: - Bindings

    func textBinding(for blockID: BlockID) -> Binding<String> {
        Binding(
            get: { document.block(for: blockID)?.textContent ?? "" },
            set: { document.updateText(blockID: blockID, text: $0) }
        )
    }

    func languageBinding(for blockID: BlockID) -> Binding<String> {
        Binding(
            get: {
                if case let .codeBlock(_, language, _) = document.block(for: blockID) {
                    return language
                }
                return ""
            },
            set: { newLanguage in
                if case let .codeBlock(id, _, code) = document.block(for: blockID) {
                    document.replaceBlock(id: id, with: .codeBlock(id: id, language: newLanguage, code: code))
                }
            }
        )
    }

    func codeBinding(for blockID: BlockID) -> Binding<String> {
        Binding(
            get: {
                if case let .codeBlock(_, _, code) = document.block(for: blockID) {
                    return code
                }
                return ""
            },
            set: { document.updateText(blockID: blockID, text: $0) }
        )
    }

    func listItemTextBinding(blockID: BlockID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let block = document.block(for: blockID) else { return "" }
                switch block {
                case let .bulletList(_, items), let .numberedList(_, items):
                    return items.first(where: { $0.id == itemID })?.text ?? ""
                default:
                    return ""
                }
            },
            set: { document.updateListItemText(blockID: blockID, itemID: itemID, text: $0) }
        )
    }

    func checkboxItemTextBinding(blockID: BlockID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                if case let .checkboxList(_, items) = document.block(for: blockID) {
                    return items.first(where: { $0.id == itemID })?.text ?? ""
                }
                return ""
            },
            set: { document.updateListItemText(blockID: blockID, itemID: itemID, text: $0) }
        )
    }

    // MARK: - Reusable Editable Text View (NSTextView, always shown with WYSIWYG styling)

    func editableTextView(
        id: BlockID,
        text: Binding<String>,
        font: NSFont = .systemFont(ofSize: 15),
        textColor: NSColor = .labelColor,
        lineSpacing: CGFloat? = nil,
        isFocused: Bool = true,
        autoCapitalize: Bool = true,
        searchHighlights: [(range: NSRange, isCurrent: Bool)] = [],
        headingLevel: Int? = nil,
        onEnter: ((_ cursorOffset: Int) -> Void)? = nil,
        onBackspaceAtStart: (() -> Void)? = nil,
        onSlashAtStart: (() -> Void)? = nil,
        onMultiBlockPaste: ((_ markdown: String) -> Void)? = nil
    ) -> some View {
        BlockTextView(
            text: text,
            font: font,
            textColor: textColor,
            lineSpacing: lineSpacing ?? fontSize * 0.25,
            isFocused: isFocused && !isBlockSelected,
            autoCapitalize: autoCapitalize,
            searchHighlights: searchHighlights,
            headingLevel: headingLevel,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onArrowUp: { xPos in focusPrevious(before: id, cursorXPosition: xPos) },
            onArrowDown: { xPos in focusNext(after: id, cursorXPosition: xPos) },
            onSlashAtStart: onSlashAtStart,
            onDeleteForwardAtEnd: { document.mergeWithNext(id: id) },
            onTextChange: { document.updateText(blockID: id, text: $0) },
            onFocusGained: { focusedBlockID = id },
            onMultiBlockPaste: onMultiBlockPaste,
            onSelectAllBlocks: onSelectAllBlocks,
            onShiftArrowUpAtTop: onShiftArrowUpAtTop,
            onShiftArrowDownAtBottom: onShiftArrowDownAtBottom,
            suggestions: suggestions,
            highlightedSuggestionID: highlightedSuggestionID,
            onHighlightedSuggestionConsumed: onHighlightedSuggestionConsumed,
            onSuggestionAccepted: onSuggestionAccepted,
            onSuggestionDismissed: onSuggestionDismissed,
            pendingCursorOffset: $pendingCursorOffset,
            pendingCursorXPosition: $pendingCursorXPosition,
            goalColumnX: $goalColumnX,
            onSelectionChange: onSelectionChange
        )
    }

    // MARK: - Reusable Editable List Item View

    enum ListType { case bullet, numbered }

    func editableListItemView(
        blockID: BlockID,
        item: BlockListItem,
        items: [BlockListItem],
        listType: ListType,
        isFocused: Bool = true,
        searchHighlights: [(range: NSRange, isCurrent: Bool)] = []
    ) -> some View {
        editableListItemContent(
            blockID: blockID,
            itemID: item.id,
            itemText: item.text,
            itemCount: items.count,
            itemIDs: items.map(\.id),
            textBinding: listItemTextBinding(blockID: blockID, itemID: item.id),
            includeTab: true,
            isFocused: isFocused,
            searchHighlights: searchHighlights
        )
    }

    func editableCheckboxItemView(
        blockID: BlockID,
        item: CheckboxItem,
        items: [CheckboxItem],
        isFocused: Bool = true,
        searchHighlights: [(range: NSRange, isCurrent: Bool)] = []
    ) -> some View {
        editableListItemContent(
            blockID: blockID,
            itemID: item.id,
            itemText: item.text,
            itemCount: items.count,
            itemIDs: items.map(\.id),
            textBinding: checkboxItemTextBinding(blockID: blockID, itemID: item.id),
            textColor: item.isChecked ? .secondaryLabelColor : .labelColor,
            isFocused: isFocused,
            searchHighlights: searchHighlights
        )
    }

    func editableListItemContent(
        blockID: BlockID,
        itemID: UUID,
        itemText: String,
        itemCount: Int,
        itemIDs: [UUID],
        textBinding: Binding<String>,
        textColor: NSColor = .labelColor,
        includeTab: Bool = false,
        isFocused: Bool = true,
        searchHighlights: [(range: NSRange, isCurrent: Bool)] = []
    ) -> some View {
        BlockTextView(
            text: textBinding,
            font: .systemFont(ofSize: fontSize),
            textColor: textColor,
            lineSpacing: fontSize * 0.25,
            isFocused: isFocused && !isBlockSelected,
            searchHighlights: searchHighlights,
            onEnter: { cursorOffset in
                if itemText.isEmpty {
                    document.removeBlockListItem(from: blockID, itemID: itemID)
                    let newBlock = Block.emptyParagraph()
                    document.insertBlock(newBlock, after: blockID)
                    focusedBlockID = newBlock.id
                    pendingCursorOffset = 0
                } else if let newItemID = document.splitListItem(blockID: blockID, itemID: itemID, atOffset: cursorOffset) {
                    focusedItemID = newItemID
                    pendingCursorOffset = 0
                }
            },
            onBackspaceAtStart: {
                handleListItemBackspace(blockID: blockID, itemID: itemID, itemText: itemText, itemCount: itemCount, itemIDs: itemIDs)
            },
            onArrowUp: { xPos in
                if let idx = itemIDs.firstIndex(of: itemID), idx > 0 {
                    focusedItemID = itemIDs[idx - 1]
                    pendingCursorOffset = document.listItemText(blockID: blockID, itemID: itemIDs[idx - 1])?.count ?? 0
                    pendingCursorXPosition = goalColumnX ?? xPos
                } else {
                    focusPrevious(before: blockID, cursorXPosition: xPos)
                }
            },
            onArrowDown: { xPos in
                if let idx = itemIDs.firstIndex(of: itemID), idx + 1 < itemIDs.count {
                    focusedItemID = itemIDs[idx + 1]
                    pendingCursorOffset = 0
                    pendingCursorXPosition = goalColumnX ?? xPos
                } else {
                    focusNext(after: blockID, cursorXPosition: xPos)
                }
            },
            onTab: includeTab ? { document.indentBlockListItem(blockID: blockID, itemID: itemID) } : nil,
            onBackTab: includeTab ? { document.outdentBlockListItem(blockID: blockID, itemID: itemID) } : nil,
            onTextChange: { document.updateListItemText(blockID: blockID, itemID: itemID, text: $0) },
            onFocusGained: {
                focusedBlockID = blockID
                focusedItemID = itemID
            },
            suggestions: suggestionsForItem(itemText),
            onSuggestionAccepted: onSuggestionAccepted,
            onSuggestionDismissed: onSuggestionDismissed,
            pendingCursorOffset: $pendingCursorOffset,
            pendingCursorXPosition: $pendingCursorXPosition,
            goalColumnX: $goalColumnX,
            onSelectionChange: onSelectionChange
        )
    }

    /// Filters block-level suggestions to those whose original text appears in the given item text.
    private func suggestionsForItem(_ itemText: String) -> [Suggestion] {
        guard !itemText.isEmpty, !suggestions.isEmpty else { return [] }
        let nsText = itemText as NSString
        return suggestions.filter { suggestion in
            nsText.range(of: suggestion.original).location != NSNotFound
        }
    }

    private func handleListItemBackspace(blockID: BlockID, itemID: UUID, itemText: String, itemCount: Int, itemIDs: [UUID]) {
        if itemCount == 1 {
            document.replaceBlock(id: blockID, with: .paragraph(id: blockID, text: itemText))
            focusedBlockID = blockID
            focusedItemID = nil
            pendingCursorOffset = 0
        } else if let idx = itemIDs.firstIndex(of: itemID) {
            if idx > 0 {
                let prevItemID = itemIDs[idx - 1]
                if itemText.isEmpty {
                    document.removeBlockListItem(from: blockID, itemID: itemID)
                    focusedItemID = prevItemID
                    pendingCursorOffset = document.listItemText(blockID: blockID, itemID: prevItemID)?.count ?? 0
                } else {
                    let prevText = document.listItemText(blockID: blockID, itemID: prevItemID) ?? ""
                    document.mergeListItemWithPrevious(blockID: blockID, itemID: itemID)
                    focusedItemID = prevItemID
                    pendingCursorOffset = prevText.count
                }
            } else if itemText.isEmpty, idx + 1 < itemIDs.count {
                let nextItemID = itemIDs[idx + 1]
                document.removeBlockListItem(from: blockID, itemID: itemID)
                focusedItemID = nextItemID
                pendingCursorOffset = 0
            }
        }
    }

    /// Finds the next item after a given item in a list block and focuses it.
    func focusNextListItem(blockID: BlockID, afterItemID: UUID) {
        guard let block = document.block(for: blockID) else { return }
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            if let idx = items.firstIndex(where: { $0.id == afterItemID }), idx + 1 < items.count {
                focusedItemID = items[idx + 1].id
            }
        case let .checkboxList(_, items):
            if let idx = items.firstIndex(where: { $0.id == afterItemID }), idx + 1 < items.count {
                focusedItemID = items[idx + 1].id
            }
        default: break
        }
    }

    // MARK: - Gutter Controls

    var addBlockMenu: some View {
        Menu {
            ForEach(BlockType.groupedByCategory, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.types, id: \.rawValue) { blockType in
                        Button {
                            let newBlock = blockType.makeEmptyBlock()
                            document.insertBlock(newBlock, after: block.id)
                            focusBlock(newBlock)
                        } label: {
                            Label(blockType.displayName, systemImage: blockType.iconName)
                        }
                    }
                }
            }
        } label: {
            GutterIcon(systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add block below")
        .accessibilityLabel("Add block below")
    }

    var dragHandleMenu: some View {
        Menu {
            turnIntoMenuItems
            Button("Duplicate") {
                let copy = duplicateBlock(block)
                document.insertBlock(copy, after: block.id)
                focusedBlockID = copy.id
            }
            Button("Delete", role: .destructive) {
                if let fallbackIdx = document.removeBlock(id: block.id) {
                    focusedBlockID = document.blocks[fallbackIdx].id
                }
            }
        } label: {
            GutterIcon(text: "⋮⋮")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Block options")
        .accessibilityLabel("Block options")
    }

    // MARK: - Fonts

    static let headingScales: [CGFloat] = [2.0, 1.5, 1.25, 1.0, 0.875, 0.85]

    static let headingFontCache = NSCache<NSNumber, NSFont>()

    func headingFont(level: Int) -> NSFont {
        let clampedLevel = max(1, min(level, 6))
        let scale = Self.headingScales[clampedLevel - 1]
        let size = fontSize * scale
        let key = NSNumber(value: Double(size))
        if let cached = Self.headingFontCache.object(forKey: key) {
            return cached
        }
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        Self.headingFontCache.setObject(font, forKey: key)
        return font
    }

    func headingLineSpacing(level: Int) -> CGFloat {
        let headingFontSize = fontSize * Self.headingScales[max(1, min(level, 6)) - 1]
        return headingFontSize * 0.125
    }

    /// Cached per fontSize to avoid recalculating NSFont metrics on every render.
    var firstLineHeight: CGFloat {
        Self.cachedFirstLineHeight(for: fontSize)
    }

    static let firstLineHeightCache = NSCache<NSNumber, NSNumber>()

    static func cachedFirstLineHeight(for fontSize: CGFloat) -> CGFloat {
        let key = NSNumber(value: Double(fontSize))
        if let cached = firstLineHeightCache.object(forKey: key) {
            return CGFloat(cached.doubleValue)
        }
        let nsFont = NSFont.systemFont(ofSize: fontSize)
        let lineHeight = nsFont.ascender - nsFont.descender + nsFont.leading
        let lineSpacing = fontSize * 0.25
        let result = ceil(lineHeight + lineSpacing)
        firstLineHeightCache.setObject(NSNumber(value: Double(result)), forKey: key)
        return result
    }

    // MARK: - List Markers (Textual-style hierarchical)

    @ViewBuilder
    func bulletMarker(indent: Int) -> some View {
        let markerLevel = indent % 3
        Group {
            switch markerLevel {
            case 0:
                Circle().fill(Color.primary.opacity(AppThemeConstants.opacityMuted)).frame(width: 5.5, height: 5.5)
            case 1:
                Circle().strokeBorder(Color.primary.opacity(AppThemeConstants.opacityMuted), lineWidth: 1).frame(width: 5.5, height: 5.5)
            default:
                Rectangle().fill(Color.primary.opacity(AppThemeConstants.opacityMuted)).frame(width: 5, height: 5)
            }
        }
        .frame(height: firstLineHeight)
    }

    // MARK: - Spacing

    var spacingForBlock: CGFloat {
        switch block {
        case .heading:
            12
        case .paragraph:
            fontSize * 0.1
        case .codeBlock:
            fontSize * 0.4
        case .blockQuote:
            fontSize * 0.4
        case .divider:
            0
        case .table:
            fontSize * 0.8
        default:
            fontSize * 0.4
        }
    }
}
