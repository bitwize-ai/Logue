import Foundation

/// Tracks multi-block selection state for the block editor.
/// When active, entire blocks are highlighted and keyboard shortcuts
/// (Copy, Cut, Delete) operate on the selected set.
@Observable
@MainActor
final class MultiBlockSelectionState {
    /// The set of currently selected block IDs. Empty means no multi-block selection.
    var selectedBlockIDs: Set<BlockID> = []

    /// The anchor block for shift-click range selection.
    var anchorBlockID: BlockID?

    /// The block where a drag gesture started (for mouse drag selection).
    var dragOriginBlockID: BlockID?

    /// Whether multi-block selection mode is active.
    var isActive: Bool {
        !selectedBlockIDs.isEmpty
    }

    func clear() {
        selectedBlockIDs.removeAll()
        anchorBlockID = nil
        dragOriginBlockID = nil
    }

    /// Selects all blocks in the contiguous range between two indices.
    func selectRange(from startIndex: Int, to endIndex: Int, in blocks: [Block]) {
        let lo = min(startIndex, endIndex)
        let hi = max(startIndex, endIndex)
        guard lo >= 0, hi < blocks.count else { return }
        selectedBlockIDs = Set(blocks[lo ... hi].map(\.id))
    }

    /// Selects every block in the document.
    func selectAll(blocks: [Block]) {
        selectedBlockIDs = Set(blocks.map(\.id))
        anchorBlockID = blocks.first?.id
    }
}
