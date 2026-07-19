import Foundation

/// The central document model for the block-based editor.
/// Holds an ordered array of blocks and provides mutation operations with undo support.
@Observable
@MainActor
final class BlockEditorDocument {
    var blocks: [Block] = [.emptyParagraph()]

    /// Incremented on table mutations to work around reference-type snapshot sharing
    /// in `onChange(of: blocks)` — since `TableBlockData` is a class, old/new array
    /// snapshots share the same instance, defeating Equatable-based change detection.
    var tableChangeCounter: Int = 0

    /// External undo manager, typically provided by the SwiftUI environment.
    var undoManager: UndoManager?

    // MARK: - Lookup

    func index(of blockID: BlockID) -> Int? {
        blocks.firstIndex(where: { $0.id == blockID })
    }

    func block(for blockID: BlockID) -> Block? {
        blocks.first(where: { $0.id == blockID })
    }

    // MARK: - Insert

    func insertBlock(_ block: Block, after blockID: BlockID) {
        guard let idx = index(of: blockID) else { return }
        let insertIdx = idx + 1
        recordUndo()
        blocks.insert(block, at: insertIdx)
    }

    func insertBlock(_ block: Block, at insertIndex: Int) {
        let clamped = max(0, min(insertIndex, blocks.count))
        recordUndo()
        blocks.insert(block, at: clamped)
    }

    // MARK: - Remove

    @discardableResult
    func removeBlock(id: BlockID) -> Int? {
        guard let idx = index(of: id) else { return nil }
        recordUndo()
        blocks.remove(at: idx)
        // Ensure document always has at least one block
        if blocks.isEmpty {
            blocks.append(.emptyParagraph())
        }
        return min(idx, blocks.count - 1)
    }

    /// Removes multiple blocks by their IDs in a single undo group.
    /// Returns the index to focus after removal.
    @discardableResult
    func removeBlocks(ids: Set<BlockID>) -> Int? {
        guard !ids.isEmpty else { return nil }
        let firstIdx = blocks.firstIndex(where: { ids.contains($0.id) }) ?? 0
        recordUndo()
        blocks.removeAll { ids.contains($0.id) }
        if blocks.isEmpty {
            blocks.append(.emptyParagraph())
        }
        return min(firstIdx, blocks.count - 1)
    }

    // MARK: - Replace

    func replaceBlock(id: BlockID, with newBlock: Block) {
        guard let idx = index(of: id) else { return }
        recordUndo()
        blocks[idx] = newBlock
    }

    // MARK: - Move

    func moveBlock(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < blocks.count,
              destinationIndex >= 0, destinationIndex <= blocks.count
        else { return }
        recordUndo()
        let block = blocks.remove(at: sourceIndex)
        let adjustedDest = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        blocks.insert(block, at: adjustedDest)
    }

    // MARK: - Update Text

    func updateText(blockID: BlockID, text: String) {
        guard let idx = index(of: blockID) else { return }
        // No undo for character-level edits — NSTextView handles that internally
        blocks[idx].textContent = text
    }

    // MARK: - Update Table Data

    /// Notifies the document that table data was mutated in-place.
    func updateTableData(blockID: BlockID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()
        if case let .table(id, data) = blocks[idx] {
            // Bump version so Equatable detects the change
            data.version += 1
            blocks[idx] = .table(id: id, data: data)
            // Bump counter so onChange(of: tableChangeCounter) fires reliably
            // (onChange(of: blocks) fails because old/new snapshots share the same TableBlockData reference)
            tableChangeCounter += 1
        }
    }

    // MARK: - Split Block

    /// Splits a text block at the given character offset.
    /// Returns the ID of the newly created block (inserted after the current one).
    @discardableResult
    func splitBlock(id: BlockID, atOffset offset: Int) -> BlockID? {
        guard let idx = index(of: id) else { return nil }
        let current = blocks[idx]

        guard let fullText = current.textContent else { return nil }

        let splitIndex = fullText.index(fullText.startIndex, offsetBy: min(offset, fullText.count))
        let before = String(fullText[..<splitIndex])
        let after = String(fullText[splitIndex...])

        recordUndo()

        // Update current block with text before split
        var updated = current
        updated.textContent = before
        blocks[idx] = updated

        // Create new paragraph with text after split
        let newID = UUID()
        let newBlock = Block.paragraph(id: newID, text: after)
        blocks.insert(newBlock, at: idx + 1)

        return newID
    }

    // MARK: - Merge With Previous

    /// Merges a text block with the previous text block.
    /// Returns the cursor offset where the merge happened (end of previous block's text).
    @discardableResult
    func mergeWithPrevious(id: BlockID) -> (blockID: BlockID, cursorOffset: Int)? {
        guard let idx = index(of: id), idx > 0 else { return nil }

        let current = blocks[idx]
        let previous = blocks[idx - 1]

        // Only merge text blocks
        guard let currentText = current.textContent,
              let previousText = previous.textContent
        else { return nil }

        let cursorOffset = previousText.count

        recordUndo()

        // Merge text into previous block
        var merged = previous
        merged.textContent = previousText + currentText
        blocks[idx - 1] = merged

        // Remove current block
        blocks.remove(at: idx)

        return (previous.id, cursorOffset)
    }

    /// Merges the next block's text into the current block.
    /// Returns true if successful.
    @discardableResult
    func mergeWithNext(id: BlockID) -> Bool {
        guard let idx = index(of: id), idx + 1 < blocks.count else { return false }
        let current = blocks[idx]
        let next = blocks[idx + 1]
        guard let currentText = current.textContent,
              let nextText = next.textContent
        else { return false }
        recordUndo()
        var merged = current
        merged.textContent = currentText + nextText
        blocks[idx] = merged
        blocks.remove(at: idx + 1)
        return true
    }

    // MARK: - List Item Operations

    func addBlockListItem(to blockID: BlockID, after itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()

        switch blocks[idx] {
        case .bulletList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let indent = items[itemIdx].indent
                items.insert(BlockListItem(indent: indent), at: itemIdx + 1)
                blocks[idx] = .bulletList(id: id, items: items)
            }

        case .numberedList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let indent = items[itemIdx].indent
                items.insert(BlockListItem(indent: indent), at: itemIdx + 1)
                blocks[idx] = .numberedList(id: id, items: items)
            }

        case .checkboxList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let indent = items[itemIdx].indent
                items.insert(CheckboxItem(indent: indent), at: itemIdx + 1)
                blocks[idx] = .checkboxList(id: id, items: items)
            }

        default:
            break
        }
    }

    /// Splits a list item at the given character offset.
    /// Text before offset stays in current item, text after goes to a new item.
    @discardableResult
    func splitListItem(blockID: BlockID, itemID: UUID, atOffset offset: Int) -> UUID? {
        guard let idx = index(of: blockID) else { return nil }
        recordUndo()

        switch blocks[idx] {
        case .bulletList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }) else { return nil }
            let fullText = items[itemIdx].text
            let splitIndex = fullText.index(fullText.startIndex, offsetBy: min(offset, fullText.count))
            items[itemIdx].text = String(fullText[..<splitIndex])
            let newItem = BlockListItem(text: String(fullText[splitIndex...]), indent: items[itemIdx].indent)
            items.insert(newItem, at: itemIdx + 1)
            blocks[idx] = .bulletList(id: id, items: items)
            return newItem.id

        case .numberedList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }) else { return nil }
            let fullText = items[itemIdx].text
            let splitIndex = fullText.index(fullText.startIndex, offsetBy: min(offset, fullText.count))
            items[itemIdx].text = String(fullText[..<splitIndex])
            let newItem = BlockListItem(text: String(fullText[splitIndex...]), indent: items[itemIdx].indent)
            items.insert(newItem, at: itemIdx + 1)
            blocks[idx] = .numberedList(id: id, items: items)
            return newItem.id

        case .checkboxList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }) else { return nil }
            let fullText = items[itemIdx].text
            let splitIndex = fullText.index(fullText.startIndex, offsetBy: min(offset, fullText.count))
            items[itemIdx].text = String(fullText[..<splitIndex])
            let newItem = CheckboxItem(text: String(fullText[splitIndex...]), indent: items[itemIdx].indent)
            items.insert(newItem, at: itemIdx + 1)
            blocks[idx] = .checkboxList(id: id, items: items)
            return newItem.id

        default:
            return nil
        }
    }

    func duplicateListItem(in blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()

        switch blocks[idx] {
        case .bulletList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let copy = BlockListItem(text: items[itemIdx].text, indent: items[itemIdx].indent)
                items.insert(copy, at: itemIdx + 1)
                blocks[idx] = .bulletList(id: id, items: items)
            }

        case .numberedList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let copy = BlockListItem(text: items[itemIdx].text, indent: items[itemIdx].indent)
                items.insert(copy, at: itemIdx + 1)
                blocks[idx] = .numberedList(id: id, items: items)
            }

        case .checkboxList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                let copy = CheckboxItem(text: items[itemIdx].text, isChecked: items[itemIdx].isChecked, indent: items[itemIdx].indent)
                items.insert(copy, at: itemIdx + 1)
                blocks[idx] = .checkboxList(id: id, items: items)
            }

        default:
            break
        }
    }

    func insertListItem(in blockID: BlockID, after itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()
        let newItem = BlockListItem(text: "")

        switch blocks[idx] {
        case .bulletList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items.insert(newItem, at: itemIdx + 1)
            } else {
                items.append(newItem)
            }
            blocks[idx] = .bulletList(id: id, items: items)

        case .numberedList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items.insert(newItem, at: itemIdx + 1)
            } else {
                items.append(newItem)
            }
            blocks[idx] = .numberedList(id: id, items: items)

        case .checkboxList(let id, var items):
            let newCheckboxItem = CheckboxItem(text: "")
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items.insert(newCheckboxItem, at: itemIdx + 1)
            } else {
                items.append(newCheckboxItem)
            }
            blocks[idx] = .checkboxList(id: id, items: items)

        default:
            break
        }
    }

    func deleteListItem(in blockID: BlockID, itemID: UUID) {
        removeBlockListItem(from: blockID, itemID: itemID)
    }

    func removeBlockListItem(from blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()

        switch blocks[idx] {
        case .bulletList(let id, var items):
            items.removeAll { $0.id == itemID }
            if items.isEmpty {
                blocks[idx] = .emptyParagraph()
            } else {
                blocks[idx] = .bulletList(id: id, items: items)
            }

        case .numberedList(let id, var items):
            items.removeAll { $0.id == itemID }
            if items.isEmpty {
                blocks[idx] = .emptyParagraph()
            } else {
                blocks[idx] = .numberedList(id: id, items: items)
            }

        case .checkboxList(let id, var items):
            items.removeAll { $0.id == itemID }
            if items.isEmpty {
                blocks[idx] = .emptyParagraph()
            } else {
                blocks[idx] = .checkboxList(id: id, items: items)
            }

        default:
            break
        }
    }

    func updateListItemText(blockID: BlockID, itemID: UUID, text: String) {
        guard let idx = index(of: blockID) else { return }

        switch blocks[idx] {
        case .bulletList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items[itemIdx].text = text
                blocks[idx] = .bulletList(id: id, items: items)
            }

        case .numberedList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items[itemIdx].text = text
                blocks[idx] = .numberedList(id: id, items: items)
            }

        case .checkboxList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                items[itemIdx].text = text
                blocks[idx] = .checkboxList(id: id, items: items)
            }

        default:
            break
        }
    }

    func toggleCheckbox(blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()
        if case .checkboxList(let id, var items) = blocks[idx],
           let itemIdx = items.firstIndex(where: { $0.id == itemID })
        {
            items[itemIdx].isChecked.toggle()

            // Auto-sort: move checked items to the bottom (preserving relative order)
            if UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.autoSortCheckedItems) {
                let unchecked = items.filter { !$0.isChecked }
                let checked = items.filter(\.isChecked)
                items = unchecked + checked
            }

            blocks[idx] = .checkboxList(id: id, items: items)
        }
    }

    func listItemText(blockID: BlockID, itemID: UUID) -> String? {
        guard let block = block(for: blockID) else { return nil }
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            return items.first(where: { $0.id == itemID })?.text
        case let .checkboxList(_, items):
            return items.first(where: { $0.id == itemID })?.text
        default:
            return nil
        }
    }

    func mergeListItemWithPrevious(blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()

        switch blocks[idx] {
        case .bulletList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }), itemIdx > 0 else { return }
            items[itemIdx - 1].text += items[itemIdx].text
            items.remove(at: itemIdx)
            blocks[idx] = .bulletList(id: id, items: items)

        case .numberedList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }), itemIdx > 0 else { return }
            items[itemIdx - 1].text += items[itemIdx].text
            items.remove(at: itemIdx)
            blocks[idx] = .numberedList(id: id, items: items)

        case .checkboxList(let id, var items):
            guard let itemIdx = items.firstIndex(where: { $0.id == itemID }), itemIdx > 0 else { return }
            items[itemIdx - 1].text += items[itemIdx].text
            items.remove(at: itemIdx)
            blocks[idx] = .checkboxList(id: id, items: items)

        default:
            break
        }
    }

    func indentBlockListItem(blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()
        mutateBlockListItem(at: idx, itemID: itemID) { $0.indent = min($0.indent + 1, 3) }
    }

    func outdentBlockListItem(blockID: BlockID, itemID: UUID) {
        guard let idx = index(of: blockID) else { return }
        recordUndo()
        mutateBlockListItem(at: idx, itemID: itemID) { $0.indent = max($0.indent - 1, 0) }
    }

    // MARK: - Markdown Roundtrip

    func loadFromMarkdown(_ markdown: String) {
        blocks = BlockSerializer.parse(markdown: markdown)
        if blocks.isEmpty {
            blocks = [.emptyParagraph()]
        }
    }

    func toMarkdown() -> String {
        BlockSerializer.serialize(blocks: blocks)
    }

    // MARK: - Undo

    private func recordUndo() {
        guard let undoManager else { return }
        let snapshot = blocks
        undoManager.registerUndo(withTarget: self) { target in
            let current = target.blocks
            target.blocks = snapshot
            // Register redo
            target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                redoTarget.blocks = current
            }
        }
    }

    // MARK: - Private Helpers

    private func mutateBlockListItem(at blockIndex: Int, itemID: UUID, mutate: (inout BlockListItem) -> Void) {
        switch blocks[blockIndex] {
        case .bulletList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                mutate(&items[itemIdx])
                blocks[blockIndex] = .bulletList(id: id, items: items)
            }

        case .numberedList(let id, var items):
            if let itemIdx = items.firstIndex(where: { $0.id == itemID }) {
                mutate(&items[itemIdx])
                blocks[blockIndex] = .numberedList(id: id, items: items)
            }

        default:
            break
        }
    }
}
