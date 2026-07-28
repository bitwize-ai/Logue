import SwiftUI

// MARK: - Block Reordering

extension BlockEditorView {
    /// Moves the current multi-block selection one position up or down and syncs
    /// the markdown binding.
    ///
    /// Falls back to the focused block when no multi-block selection is active, so
    /// Cmd+Shift+Up/Down works while simply editing a block.
    func moveSelectedBlocks(_ direction: BlockEditorDocument.MoveDirection) {
        let selectedIDs: Set<BlockID>
        if multiBlockSelection.isActive {
            selectedIDs = multiBlockSelection.selectedBlockIDs
        } else if let focused = focusedBlockID {
            selectedIDs = [focused]
        } else {
            return
        }

        document.moveSelectedBlocks(selectedIDs, direction: direction)
        syncMarkdownFromBlocks()
    }
}

// MARK: - Block Paste

extension BlockEditorView {
    /// Replaces the multi-block selection with the clipboard's markdown.
    ///
    /// Only acts while a multi-block selection is active — inside a focused text
    /// block, `BlockTextView.paste(_:)` owns the clipboard instead.
    func pasteOverSelectedBlocks() {
        guard multiBlockSelection.isActive,
              let markdown = NSPasteboard.general.string(forType: .string)
        else { return }

        let selectedIDs = multiBlockSelection.selectedBlockIDs
        multiBlockSelection.clear()

        guard let focusTarget = document.replaceBlocks(ids: selectedIDs, withMarkdown: markdown)
        else { return }

        focusedBlockID = focusTarget
        syncMarkdownFromBlocks()
    }
}

// MARK: - Markdown Sync

extension BlockEditorView {
    /// Serialises the block model back into the markdown binding.
    ///
    /// Records the result in `lastSyncedMarkdown` so the binding's `onChange`
    /// handler can recognise our own output and skip re-parsing it.
    func syncMarkdownFromBlocks() {
        guard isLoaded else { return }
        let newMarkdown = document.toMarkdown()
        if newMarkdown != markdownText {
            lastSyncedMarkdown = newMarkdown
            markdownText = newMarkdown
        }
    }
}
