import Foundation
@testable import Logue
import Testing

@Suite("BlockMove")
@MainActor
struct BlockMoveTests {
    private func document(count: Int) -> BlockEditorDocument {
        let doc = BlockEditorDocument()
        doc.blocks = (0 ..< count).map { .paragraph(id: UUID(), text: "block \($0)") }
        return doc
    }

    private func texts(_ doc: BlockEditorDocument) -> [String] {
        doc.blocks.compactMap(\.textContent)
    }

    @Test("Moving a single selected block up swaps it with the one above")
    func moveSingleBlockUp() {
        let doc = document(count: 3)
        let selection = MultiBlockSelectionState()
        selection.selectedBlockIDs = [doc.blocks[1].id]

        doc.moveSelectedBlocks(selection.selectedBlockIDs, direction: .up)

        #expect(texts(doc) == ["block 1", "block 0", "block 2"])
    }

    @Test("Moving a single selected block down swaps it with the one below")
    func moveSingleBlockDown() {
        let doc = document(count: 3)
        let selection = MultiBlockSelectionState()
        selection.selectedBlockIDs = [doc.blocks[1].id]

        doc.moveSelectedBlocks(selection.selectedBlockIDs, direction: .down)

        #expect(texts(doc) == ["block 0", "block 2", "block 1"])
    }

    @Test("A contiguous multi-block selection moves as one unit and keeps its order")
    func moveContiguousRangeDown() {
        let doc = document(count: 4)
        let ids: Set<BlockID> = [doc.blocks[0].id, doc.blocks[1].id]

        doc.moveSelectedBlocks(ids, direction: .down)

        #expect(texts(doc) == ["block 2", "block 0", "block 1", "block 3"])
    }

    @Test("A contiguous multi-block selection moves up as one unit")
    func moveContiguousRangeUp() {
        let doc = document(count: 4)
        let ids: Set<BlockID> = [doc.blocks[2].id, doc.blocks[3].id]

        doc.moveSelectedBlocks(ids, direction: .up)

        #expect(texts(doc) == ["block 0", "block 2", "block 3", "block 1"])
    }

    @Test("Moving the top block up leaves the document unchanged")
    func moveTopBlockUpIsNoOp() {
        let doc = document(count: 3)
        doc.moveSelectedBlocks([doc.blocks[0].id], direction: .up)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])
    }

    @Test("Moving the bottom block down leaves the document unchanged")
    func moveBottomBlockDownIsNoOp() {
        let doc = document(count: 3)
        doc.moveSelectedBlocks([doc.blocks[2].id], direction: .down)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])
    }

    @Test("An empty selection leaves the document unchanged")
    func emptySelectionIsNoOp() {
        let doc = document(count: 3)
        doc.moveSelectedBlocks([], direction: .up)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])
    }

    @Test("A non-contiguous selection is rejected rather than reordered arbitrarily")
    func nonContiguousSelectionIsRejected() {
        let doc = document(count: 4)
        let ids: Set<BlockID> = [doc.blocks[0].id, doc.blocks[2].id]

        doc.moveSelectedBlocks(ids, direction: .down)

        #expect(texts(doc) == ["block 0", "block 1", "block 2", "block 3"])
    }

    @Test("Selecting every block and moving is a no-op in both directions")
    func fullSelectionIsNoOp() {
        let doc = document(count: 3)
        let all = Set(doc.blocks.map(\.id))

        doc.moveSelectedBlocks(all, direction: .up)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])

        doc.moveSelectedBlocks(all, direction: .down)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])
    }

    @Test("Unknown block IDs are ignored")
    func unknownIDsAreIgnored() {
        let doc = document(count: 3)
        doc.moveSelectedBlocks([UUID()], direction: .down)
        #expect(texts(doc) == ["block 0", "block 1", "block 2"])
    }
}
