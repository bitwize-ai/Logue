import Foundation
@testable import Logue
import Testing

/// Pasting over a multi-block selection: the selected blocks are replaced by the
/// blocks parsed from the pasted markdown.
@Suite("BlockPaste")
@MainActor
struct BlockPasteTests {
    private func document(count: Int) -> BlockEditorDocument {
        let doc = BlockEditorDocument()
        doc.blocks = (0 ..< count).map { .paragraph(id: UUID(), text: "block \($0)") }
        return doc
    }

    private func texts(_ doc: BlockEditorDocument) -> [String] {
        doc.blocks.compactMap(\.textContent)
    }

    @Test("Pasting over one selected block replaces it")
    func replacesSingleBlock() {
        let doc = document(count: 3)
        doc.replaceBlocks(ids: [doc.blocks[1].id], withMarkdown: "pasted")
        #expect(texts(doc) == ["block 0", "pasted", "block 2"])
    }

    @Test("Pasting over a contiguous selection replaces the whole run")
    func replacesContiguousRun() {
        let doc = document(count: 4)
        let ids: Set<BlockID> = [doc.blocks[1].id, doc.blocks[2].id]
        doc.replaceBlocks(ids: ids, withMarkdown: "pasted")
        #expect(texts(doc) == ["block 0", "pasted", "block 3"])
    }

    @Test("Multi-block markdown expands into multiple blocks")
    func expandsIntoMultipleBlocks() {
        let doc = document(count: 2)
        doc.replaceBlocks(ids: [doc.blocks[0].id], withMarkdown: "one\n\ntwo")
        #expect(texts(doc) == ["one", "two", "block 1"])
    }

    @Test("Pasted markdown keeps its block structure")
    func preservesBlockStructure() {
        let doc = document(count: 1)
        doc.replaceBlocks(ids: [doc.blocks[0].id], withMarkdown: "# Heading\n\nbody")

        #expect(doc.blocks.count == 2)
        guard case let .heading(_, level, text) = doc.blocks[0] else {
            Issue.record("Expected a heading, got \(doc.blocks[0])")
            return
        }
        #expect(level == 1)
        #expect(text == "Heading")
    }

    @Test("The returned focus target is the last pasted block")
    func returnsLastPastedBlockAsFocusTarget() {
        let doc = document(count: 2)
        let focus = doc.replaceBlocks(ids: [doc.blocks[0].id], withMarkdown: "one\n\ntwo")
        #expect(focus == doc.blocks[1].id)
    }

    @Test("Pasting empty markdown leaves the document unchanged")
    func emptyMarkdownIsNoOp() {
        let doc = document(count: 2)
        doc.replaceBlocks(ids: [doc.blocks[0].id], withMarkdown: "   ")
        #expect(texts(doc) == ["block 0", "block 1"])
    }

    @Test("Pasting with no selection leaves the document unchanged")
    func emptySelectionIsNoOp() {
        let doc = document(count: 2)
        doc.replaceBlocks(ids: [], withMarkdown: "pasted")
        #expect(texts(doc) == ["block 0", "block 1"])
    }

    @Test("Unknown block IDs are ignored")
    func unknownIDsAreIgnored() {
        let doc = document(count: 2)
        doc.replaceBlocks(ids: [UUID()], withMarkdown: "pasted")
        #expect(texts(doc) == ["block 0", "block 1"])
    }

    @Test("Replacing every block leaves a non-empty document")
    func documentNeverBecomesEmpty() {
        let doc = document(count: 2)
        doc.replaceBlocks(ids: Set(doc.blocks.map(\.id)), withMarkdown: "only")
        #expect(texts(doc) == ["only"])
        #expect(doc.blocks.isEmpty == false)
    }

    @Test("A non-contiguous selection is replaced at the first selected position")
    func nonContiguousSelectionCollapsesToFirstPosition() {
        let doc = document(count: 4)
        let ids: Set<BlockID> = [doc.blocks[1].id, doc.blocks[3].id]
        doc.replaceBlocks(ids: ids, withMarkdown: "pasted")
        #expect(texts(doc) == ["block 0", "pasted", "block 2"])
    }

    /// Guardrail: text paths must be exercised with multi-UTF-16 content, not only ASCII.
    @Test("Emoji and CJK content pastes intact")
    func unicodeContentSurvives() {
        let doc = document(count: 1)
        doc.replaceBlocks(ids: [doc.blocks[0].id], withMarkdown: "👩‍💻 記録 done")
        #expect(texts(doc) == ["👩‍💻 記録 done"])
    }
}
