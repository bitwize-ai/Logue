import Foundation
@testable import Logue
import Testing

@Suite("DocumentReplace")
@MainActor
struct DocumentReplaceTests {
    private func document(_ blocks: [Block]) -> BlockEditorDocument {
        let doc = BlockEditorDocument()
        doc.blocks = blocks
        return doc
    }

    @Test("Replacing the current match rewrites only that occurrence")
    func replacesOnlyCurrentMatch() {
        let doc = document([.paragraph(id: UUID(), text: "cat and cat")])
        let state = DocumentSearchState()
        state.query = "cat"
        state.search(in: doc.blocks)

        state.replaceCurrent(with: "dog", in: doc)

        #expect(doc.blocks[0].textContent == "dog and cat")
    }

    @Test("Replace all rewrites every occurrence across blocks")
    func replaceAllAcrossBlocks() {
        let doc = document([
            .paragraph(id: UUID(), text: "cat one"),
            .heading(id: UUID(), level: 2, text: "cat two"),
        ])
        let state = DocumentSearchState()
        state.query = "cat"
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "dog", in: doc)

        #expect(count == 2)
        #expect(doc.blocks[0].textContent == "dog one")
        #expect(doc.blocks[1].textContent == "dog two")
    }

    @Test("Replace all rewrites every occurrence inside one block")
    func replaceAllWithinOneBlock() {
        let doc = document([.paragraph(id: UUID(), text: "cat cat cat")])
        let state = DocumentSearchState()
        state.query = "cat"
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "dog", in: doc)

        #expect(count == 3)
        #expect(doc.blocks[0].textContent == "dog dog dog")
    }

    @Test("Replace all rewrites list item text")
    func replaceAllInListItems() {
        let blockID = UUID()
        let doc = document([
            .bulletList(id: blockID, items: [
                BlockListItem(text: "cat one"),
                BlockListItem(text: "cat two"),
            ]),
        ])
        let state = DocumentSearchState()
        state.query = "cat"
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "dog", in: doc)

        #expect(count == 2)
        guard case let .bulletList(_, items) = doc.blocks[0] else {
            Issue.record("Expected a bullet list, got \(doc.blocks[0])")
            return
        }
        #expect(items.map(\.text) == ["dog one", "dog two"])
    }

    @Test("Case-sensitive replace leaves differently-cased text alone")
    func caseSensitiveReplace() {
        let doc = document([.paragraph(id: UUID(), text: "Cat and cat")])
        let state = DocumentSearchState()
        state.query = "cat"
        state.matchCase = true
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "dog", in: doc)

        #expect(count == 1)
        #expect(doc.blocks[0].textContent == "Cat and dog")
    }

    @Test("Replacing with a shorter string keeps later matches aligned")
    func shorterReplacementKeepsOffsetsValid() {
        let doc = document([.paragraph(id: UUID(), text: "aaaa bbbb aaaa")])
        let state = DocumentSearchState()
        state.query = "aaaa"
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "z", in: doc)

        #expect(count == 2)
        #expect(doc.blocks[0].textContent == "z bbbb z")
    }

    @Test("Replace all with an empty query changes nothing")
    func emptyQueryIsNoOp() {
        let doc = document([.paragraph(id: UUID(), text: "untouched")])
        let state = DocumentSearchState()
        state.query = ""
        state.search(in: doc.blocks)

        let count = state.replaceAll(with: "x", in: doc)

        #expect(count == 0)
        #expect(doc.blocks[0].textContent == "untouched")
    }

    @Test("Matches are refreshed after a replacement")
    func matchesRefreshAfterReplace() {
        let doc = document([.paragraph(id: UUID(), text: "cat cat")])
        let state = DocumentSearchState()
        state.query = "cat"
        state.search(in: doc.blocks)
        #expect(state.matches.count == 2)

        state.replaceCurrent(with: "dog", in: doc)

        #expect(state.matches.count == 1)
    }

    @Test("Replacing the current match with no matches present is a no-op")
    func replaceCurrentWithoutMatchesIsNoOp() {
        let doc = document([.paragraph(id: UUID(), text: "nothing here")])
        let state = DocumentSearchState()
        state.query = "zzz"
        state.search(in: doc.blocks)

        state.replaceCurrent(with: "x", in: doc)

        #expect(doc.blocks[0].textContent == "nothing here")
    }

    /// A multi-UTF-16 character (emoji) before the match makes the UTF-16 offset
    /// exceed the grapheme count; indexing the String with that offset used to trap.
    @Test("Whole-word search is safe and correct with an emoji before the match")
    func wholeWordSearchWithLeadingEmoji() throws {
        let doc = document([.paragraph(id: UUID(), text: "👩‍💻 word and words")])
        let state = DocumentSearchState()
        state.query = "word"
        state.wholeWord = true

        state.search(in: doc.blocks)

        // Only the standalone "word" matches; the emoji is a boundary and "words" is excluded.
        #expect(state.matches.count == 1)
        let match = try #require(state.matches.first)
        let text = try #require(doc.blocks[0].textContent) as NSString
        #expect(text.substring(with: match.range) == "word")
    }
}
