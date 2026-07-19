import SwiftUI
import Textual

// MARK: - BlockRowView

// Renders a single block with hover controls (+ button, drag handle) and the block's content view.
// All text blocks use BlockTextView with MarkdownStyler for WYSIWYG rendering at all times.
// Code blocks retain two-state rendering (Textual syntax highlighting when unfocused).
// swiftlint:disable:next type_body_length
struct BlockRowView: View {
    let block: Block
    let document: BlockEditorDocument
    @Binding var focusedBlockID: BlockID?
    @Binding var focusedItemID: UUID?
    @Binding var pendingCursorOffset: Int?
    @Binding var pendingCursorXPosition: CGFloat?
    @Binding var goalColumnX: CGFloat?
    var fontSize: CGFloat
    var suggestions: [Suggestion] = []
    var onSuggestionAccepted: ((Suggestion) -> Void)?
    var onSuggestionDismissed: ((Suggestion) -> Void)?
    var onSelectionChange: ((_ textView: MarkdownNSTextView, _ range: NSRange, _ screenRect: CGRect?) -> Void)?
    /// When set, the block's text view selects the original text of the matching suggestion.
    var highlightedSuggestionID: UUID?
    /// Called after the suggestion highlight has been consumed so the parent can clear it.
    var onHighlightedSuggestionConsumed: (() -> Void)?
    var isBlockSelected: Bool = false
    var onSelectAllBlocks: (() -> Void)?
    var onShiftArrowUpAtTop: (() -> Void)?
    var onShiftArrowDownAtBottom: (() -> Void)?
    /// Search matches within this block for highlight rendering.
    var searchMatches: [SearchMatch] = []
    /// ID of the currently active search match (gets distinct highlight color).
    var currentSearchMatchID: UUID?

    @State var isHovered = false
    @State var showSlashCommand = false
    @State var showBlockOptions = false
    @State var slashTarget: SlashMenuTarget?

    var isFocused: Bool {
        focusedBlockID == block.id
    }

    static let gutterWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Gutter controls (visible on hover) — hidden for list blocks (per-item gutter used instead)
            if !block.isListBlock {
                HStack(spacing: 2) {
                    addBlockMenu
                    dragHandleMenu
                }
                .frame(width: Self.gutterWidth, alignment: .trailing)
                .padding(.trailing, 4)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
            }

            // Block content
            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(slashCommandMenuAnchor)
                .contextMenu { blockContextMenu }
        }
        .padding(.vertical, spacingForBlock)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(AppThemeConstants.brandPrimary.opacity(isBlockSelected ? 0.12 : 0))
                .allowsHitTesting(false)
        )
    }

    // MARK: - Block Content

    @ViewBuilder
    private var blockContent: some View {
        switch block {
        case let .paragraph(id, text):
            paragraphView(id: id, text: text)

        case let .heading(id, level, text):
            headingView(id: id, level: level, text: text)

        case let .bulletList(id, items):
            bulletListView(id: id, items: items)

        case let .numberedList(id, items):
            numberedListView(id: id, items: items)

        case let .checkboxList(id, items):
            checkboxListView(id: id, items: items)

        case let .blockQuote(id, text):
            blockQuoteView(id: id, text: text)

        case let .codeBlock(id, language, code):
            codeBlockView(id: id, language: language, code: code)

        case let .table(_, data):
            tableView(data: data)

        case .divider:
            dividerView()
        }
    }

    // MARK: - Textual Style Modifiers

    /// Applies the full GitHub style preset to a StructuredText view.
    private func textualStyled(_ view: some View) -> some View {
        view
            .font(.system(size: fontSize))
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(.gitHub)
    }

    // MARK: - Paragraph

    private func paragraphView(id: BlockID, text: String) -> some View {
        editableTextView(
            id: id,
            text: textBinding(for: id),
            font: .systemFont(ofSize: fontSize),
            isFocused: isFocused,
            searchHighlights: blockSearchHighlights(),
            onEnter: { offset in splitBlock(id: id, at: offset) },
            onBackspaceAtStart: {
                if !mergeWithPrevious(id: id), text.isEmpty {
                    if let idx = document.index(of: id), idx > 0 {
                        let prevBlock = document.blocks[idx - 1]
                        document.removeBlock(id: id)
                        focusedBlockID = prevBlock.id
                        switch prevBlock {
                        case let .bulletList(_, items), let .numberedList(_, items):
                            focusedItemID = items.last?.id
                        case let .checkboxList(_, items):
                            focusedItemID = items.last?.id
                        default:
                            focusedItemID = nil
                        }
                    }
                }
            },
            onSlashAtStart: { showSlashCommand = true },
            onMultiBlockPaste: { markdown in
                handleMultiBlockPaste(blockID: id, markdown: markdown)
            }
        )
        .frame(minHeight: text.isEmpty && !isFocused ? fontSize * 1.5 : 0)
    }

    // MARK: - Heading

    private func headingView(id: BlockID, level: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            editableTextView(
                id: id,
                text: textBinding(for: id),
                font: headingFont(level: level),
                textColor: level == 6 ? .tertiaryLabelColor : .labelColor,
                lineSpacing: headingLineSpacing(level: level),
                isFocused: isFocused,
                searchHighlights: blockSearchHighlights(),
                headingLevel: level,
                onEnter: { offset in
                    if text.isEmpty {
                        document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    } else {
                        splitBlock(id: id, at: offset)
                    }
                },
                onBackspaceAtStart: {
                    if text.isEmpty {
                        document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    } else {
                        mergeWithPrevious(id: id)
                    }
                }
            )
            if level <= 2 {
                Divider().padding(.top, 6)
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Heading level \(level): \(text)")
    }

    // MARK: - List Item Row Helper

    // swiftlint:disable:next function_parameter_count
    private func listItemRow(
        blockID: BlockID,
        itemID: UUID,
        itemText: String,
        indent: Int,
        isItemEditing: Bool,
        @ViewBuilder marker: () -> some View,
        @ViewBuilder editableContent: () -> some View,
        isChecked: Bool? = nil
    ) -> some View {
        let markerContent = marker()
        let editorContent = editableContent()
        let gutterContent = HStack(spacing: 2) {
            listItemAddMenu(blockID: blockID, afterItemID: itemID)
            listItemOptionsMenu(blockID: blockID, itemID: itemID)
        }

        return ListItemHoverWrapper { isItemHovered in
            HStack(alignment: .top, spacing: 0) {
                gutterContent
                    .frame(width: Self.gutterWidth, alignment: .trailing)
                    .padding(.trailing, 4)
                    .opacity(isItemHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isItemHovered)
                    .allowsHitTesting(isItemHovered)
                    .accessibilityHidden(!isItemHovered)

                HStack(alignment: .top, spacing: listMarkerSpacing) {
                    if indent > 0 {
                        Spacer().frame(width: CGFloat(indent) * listIndentWidth)
                    }
                    markerContent
                    editorContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isChecked == true
                    ? "\(itemText), completed"
                    : isChecked == false
                    ? "\(itemText), not completed"
                    : itemText
            )
        }
    }

    // MARK: - Per-Item Gutter Menus

    private func listItemAddMenu(blockID: BlockID, afterItemID: UUID) -> some View {
        Menu {
            Button {
                document.insertListItem(in: blockID, after: afterItemID)
            } label: {
                Label("New item below", systemImage: "plus")
            }
            Divider()
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
        .help("Add item or block")
    }

    private func listItemOptionsMenu(blockID: BlockID, itemID: UUID) -> some View {
        Menu {
            Button("Duplicate") {
                document.duplicateListItem(in: blockID, itemID: itemID)
            }
            Divider()
            Button("Delete", role: .destructive) {
                document.deleteListItem(in: blockID, itemID: itemID)
            }
        } label: {
            GutterIcon(text: "⋮⋮")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Item options")
    }

    // MARK: - Bullet List

    private func bulletListView(id: BlockID, items: [BlockListItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items) { item in
                let isItemFocused = isFocused && focusedItemID == item.id
                listItemRow(
                    blockID: id,
                    itemID: item.id,
                    itemText: item.text,
                    indent: item.indent,
                    isItemEditing: isItemFocused,
                    marker: { bulletMarker(indent: item.indent) },
                    editableContent: {
                        editableListItemView(
                            blockID: id,
                            item: item,
                            items: items,
                            listType: .bullet,
                            isFocused: isItemFocused,
                            searchHighlights: itemSearchHighlights(itemID: item.id)
                        )
                    }
                )
            }
        }
    }

    // MARK: - Numbered List

    private func numberedListView(id: BlockID, items: [BlockListItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isItemFocused = isFocused && focusedItemID == item.id
                listItemRow(
                    blockID: id,
                    itemID: item.id,
                    itemText: item.text,
                    indent: item.indent,
                    isItemEditing: isItemFocused,
                    marker: {
                        Text("\(index + 1).")
                            .font(.system(size: fontSize).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                            .frame(height: firstLineHeight)
                    },
                    editableContent: {
                        editableListItemView(
                            blockID: id,
                            item: item,
                            items: items,
                            listType: .numbered,
                            isFocused: isItemFocused,
                            searchHighlights: itemSearchHighlights(itemID: item.id)
                        )
                    }
                )
            }
        }
    }

    // MARK: - Checkbox List

    private func checkboxListView(id: BlockID, items: [CheckboxItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items) { item in
                let isItemFocused = isFocused && focusedItemID == item.id
                listItemRow(
                    blockID: id,
                    itemID: item.id,
                    itemText: item.text,
                    indent: item.indent,
                    isItemEditing: isItemFocused,
                    marker: {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                document.toggleCheckbox(blockID: id, itemID: item.id)
                            }
                        } label: {
                            Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.isChecked ? AppThemeConstants.accent : Color.secondary)
                                .font(.system(size: AppThemeConstants.checkboxSize))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isChecked ? "Mark incomplete" : "Mark complete")
                        .frame(height: firstLineHeight)
                    },
                    editableContent: {
                        editableCheckboxItemView(
                            blockID: id,
                            item: item,
                            items: items,
                            isFocused: isItemFocused,
                            searchHighlights: itemSearchHighlights(itemID: item.id)
                        )
                    },
                    isChecked: item.isChecked
                )
            }
        }
    }

    // MARK: - Block Quote

    private func blockQuoteView(id: BlockID, text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(AppThemeConstants.opacityStrong))
                .frame(width: blockquoteBarWidth)

            editableTextView(
                id: id,
                text: textBinding(for: id),
                font: .systemFont(ofSize: fontSize),
                textColor: .secondaryLabelColor,
                isFocused: isFocused,
                searchHighlights: blockSearchHighlights(),
                onEnter: { offset in
                    if text.isEmpty {
                        document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    } else {
                        splitBlock(id: id, at: offset)
                    }
                },
                onBackspaceAtStart: {
                    if text.isEmpty {
                        document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    } else {
                        mergeWithPrevious(id: id)
                    }
                }
            )
            .padding(.leading, fontSize * 1.0)
            .padding(.vertical, fontSize * 0.5)
        }
    }

    // MARK: - Code Block

    private func codeBlockHeader(id: BlockID, code: String) -> some View {
        HStack {
            TextField("language", text: languageBinding(for: id))
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: 120)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func codeBlockView(id: BlockID, language: String, code: String) -> some View {
        if isFocused {
            // Focused: editable NSTextView with language picker
            VStack(alignment: .leading, spacing: 0) {
                codeBlockHeader(id: id, code: code)

                BlockTextView(
                    text: codeBinding(for: id),
                    font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.882, weight: .regular),
                    textColor: .labelColor,
                    lineSpacing: 2,
                    isFocused: !isBlockSelected,
                    markdownStyleEnabled: false,
                    autoCapitalize: false,
                    searchHighlights: blockSearchHighlights(),
                    onEnter: nil,
                    onArrowUp: { xPos in focusPrevious(before: id, cursorXPosition: xPos) },
                    onArrowDown: { xPos in focusNext(after: id, cursorXPosition: xPos) },
                    onTextChange: { document.updateText(blockID: id, text: $0) },
                    onFocusGained: { focusedBlockID = id },
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(AppThemeConstants.codeBlockBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(AppThemeConstants.codeBlockBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            // Unfocused: full Textual rendering with syntax highlighting
            let fenced = "```\(language)\n\(code)\n```"
            textualStyled(StructuredText(markdown: fenced))
                .textual.overflowMode(.scroll)
                .contentShape(Rectangle())
                .onTapGesture { focusedBlockID = id }
        }
    }

    // MARK: - Table

    private func tableView(data: TableBlockData) -> some View {
        TableBlockEditView(
            blockID: block.id,
            data: data,
            document: document,
            fontSize: fontSize,
            isFocused: isFocused,
            onFocusGained: { focusedBlockID = block.id },
            onSelectionChange: onSelectionChange
        )
    }

    // MARK: - Divider (Textual thematic break)

    private func dividerView() -> some View {
        textualStyled(StructuredText(markdown: "---"))
    }
}

// MARK: - Gutter Icon

/// A small hoverable icon used for the + and ⋮⋮ gutter buttons.
struct GutterIcon: View {
    var systemImage: String?
    var text: String?
    @State private var isHovered = false

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .secondary)
            } else if let text {
                Text(text)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
            }
        }
        .frame(width: 18, height: 18)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(AppThemeConstants.hoverOpacity) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - List Item Hover Wrapper

/// Isolates hover state per list item so that hovering one item
/// doesn't re-render the entire list block.
private struct ListItemHoverWrapper<Content: View>: View {
    @ViewBuilder let content: (_ isHovered: Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        content(isHovered)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

// MARK: - Slash Menu Target

/// NSObject target for native NSMenu actions triggered by the `/` slash command.
class SlashMenuTarget: NSObject {
    let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    @objc
    func menuAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        handler(rawValue)
    }
}
