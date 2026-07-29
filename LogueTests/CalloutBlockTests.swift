import Foundation
@testable import Logue
import Testing

/// Callouts must round-trip through markdown exactly, because the markdown file is the
/// document in plain-storage mode — a lossy serialize rewrites the user's file on the next
/// save. The unrecognised-type cases matter for the same reason: anything we cannot name has
/// to survive as the block quote it already was.
@Suite("CalloutBlocks")
struct CalloutBlockTests {
    // MARK: - Parse

    @Test("Each recognised alert type parses into a callout of that kind", arguments: CalloutKind.allCases)
    func everyKindParses(kind: CalloutKind) {
        let blocks = BlockSerializer.parse(markdown: "> [!\(kind.rawValue)]\n> Body text.")

        #expect(blocks.count == 1)
        guard case let .callout(_, parsedKind, title, body) = blocks[0] else {
            Issue.record("Expected a callout, got \(blocks[0])")
            return
        }
        #expect(parsedKind == kind)
        #expect(title.isEmpty)
        #expect(body == "Body text.")
    }

    @Test("A title after the type is captured")
    func titleIsCaptured() {
        let blocks = BlockSerializer.parse(markdown: "> [!NOTE] Local-first\n> Stays readable outside the app.")

        guard case let .callout(_, kind, title, body) = blocks[0] else {
            Issue.record("Expected a callout, got \(blocks[0])")
            return
        }
        #expect(kind == .note)
        #expect(title == "Local-first")
        #expect(body == "Stays readable outside the app.")
    }

    @Test("A lower-case marker still parses")
    func lowerCaseMarker() {
        guard case let .callout(_, kind, _, _) = BlockSerializer.parse(markdown: "> [!tip]\n> Try this.")[0] else {
            Issue.record("Expected a callout for a lower-case marker")
            return
        }
        #expect(kind == .tip)
    }

    @Test("A multi-line body keeps its line breaks")
    func multiLineBody() {
        let blocks = BlockSerializer.parse(markdown: "> [!WARNING]\n> First line.\n> Second line.")

        guard case let .callout(_, _, _, body) = blocks[0] else {
            Issue.record("Expected a callout, got \(blocks[0])")
            return
        }
        #expect(body == "First line.\nSecond line.")
    }

    @Test("A callout with no body is just its header")
    func headerOnlyCallout() {
        let blocks = BlockSerializer.parse(markdown: "> [!CAUTION] Careful")

        guard case let .callout(_, kind, title, body) = blocks[0] else {
            Issue.record("Expected a callout, got \(blocks[0])")
            return
        }
        #expect(kind == .caution)
        #expect(title == "Careful")
        #expect(body.isEmpty)
    }

    // MARK: - Degrading gracefully

    @Test("An unrecognised type stays a block quote")
    func unknownTypeIsABlockQuote() {
        let blocks = BlockSerializer.parse(markdown: "> [!BANANA]\n> Still a quote.")

        #expect(blocks.count == 1)
        guard case let .blockQuote(_, text) = blocks[0] else {
            Issue.record("Expected a block quote, got \(blocks[0])")
            return
        }
        // The marker text is not dropped — it is part of the quote, as GitHub renders it.
        #expect(text.contains("[!BANANA]"))
        #expect(text.contains("Still a quote."))
    }

    @Test("A plain quote with no marker is unchanged")
    func plainQuoteUnchanged() {
        let blocks = BlockSerializer.parse(markdown: "> Just a quote.")

        guard case let .blockQuote(_, text) = blocks[0] else {
            Issue.record("Expected a block quote, got \(blocks[0])")
            return
        }
        #expect(text == "Just a quote.")
    }

    @Test("A plain quote still round-trips")
    func plainQuoteRoundTrips() {
        let markdown = "> Just a quote."
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown)) == markdown)
    }

    @Test("A bracketed marker that is not a callout does not swallow the rest of the document")
    func unknownMarkerLeavesFollowingBlocks() {
        let blocks = BlockSerializer.parse(markdown: "> [!BANANA]\n> Quote.\n\n# Heading")

        #expect(blocks.count == 2)
        guard case .blockQuote = blocks[0] else {
            Issue.record("Expected the quote first, got \(blocks[0])")
            return
        }
        guard case let .heading(_, level, text) = blocks[1] else {
            Issue.record("Expected a heading second, got \(blocks[1])")
            return
        }
        #expect(level == 1)
        #expect(text == "Heading")
    }

    // MARK: - Round-trip

    @Test("A callout with a title round-trips exactly")
    func titledRoundTrip() {
        let markdown = "> [!NOTE] Local-first\n> This note stays readable outside the app."
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown)) == markdown)
    }

    @Test("A callout without a title round-trips exactly")
    func untitledRoundTrip() {
        let markdown = "> [!WARNING]\n> Careful here."
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown)) == markdown)
    }

    @Test("Every kind round-trips exactly", arguments: CalloutKind.allCases)
    func everyKindRoundTrips(kind: CalloutKind) {
        let markdown = "> [!\(kind.rawValue)] A title\n> Line one.\n> Line two."
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown)) == markdown)
    }

    @Test("A blank line inside the body round-trips as a bare marker")
    func blankBodyLineRoundTrips() {
        let markdown = "> [!TIP]\n> First.\n>\n> Second."
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown)) == markdown)
    }

    @Test("A header-only callout round-trips without gaining an empty quote line")
    func headerOnlyRoundTrips() {
        #expect(BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: "> [!NOTE]")) == "> [!NOTE]")
    }

    @Test("A callout between other blocks keeps its place")
    func calloutAmongOtherBlocks() {
        let markdown = "# Title\n\n> [!IMPORTANT] Read this\n> Body.\n\nA paragraph."
        let blocks = BlockSerializer.parse(markdown: markdown)

        #expect(blocks.count == 3)
        guard case .heading = blocks[0] else {
            Issue.record("Expected a heading first, got \(blocks[0])")
            return
        }
        guard case .callout = blocks[1] else {
            Issue.record("Expected a callout second, got \(blocks[1])")
            return
        }
        guard case .paragraph = blocks[2] else {
            Issue.record("Expected a paragraph third, got \(blocks[2])")
            return
        }
        #expect(BlockSerializer.serialize(blocks: blocks) == markdown)
    }

    @Test("Two adjacent callouts stay two blocks")
    func adjacentCallouts() {
        let markdown = "> [!NOTE]\n> One.\n\n> [!TIP]\n> Two."
        let blocks = BlockSerializer.parse(markdown: markdown)

        #expect(blocks.count == 2)
        #expect(BlockSerializer.serialize(blocks: blocks) == markdown)
    }

    @Test("Lower-case markers normalise to the spelling GitHub renders")
    func lowerCaseNormalises() {
        let output = BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: "> [!note]\n> Body."))
        #expect(output == "> [!NOTE]\n> Body.")
    }

    // MARK: - Block behaviour

    @Test("A callout is a text block so its body is editable")
    func calloutIsATextBlock() {
        #expect(Block.callout(id: UUID(), kind: .note, title: "", body: "x").isTextBlock)
    }

    @Test("textContent reads and writes the body, leaving kind and title alone")
    func textContentMapsToBody() {
        var block = Block.callout(id: UUID(), kind: .warning, title: "Heads up", body: "Old")
        #expect(block.textContent == "Old")

        block.textContent = "New"
        guard case let .callout(_, kind, title, body) = block else {
            Issue.record("Expected a callout, got \(block)")
            return
        }
        #expect(kind == .warning)
        #expect(title == "Heads up")
        #expect(body == "New")
    }

    @Test("A callout is empty only when both title and body are blank")
    func emptiness() {
        #expect(Block.callout(id: UUID(), kind: .note, title: "", body: "   ").isEmpty)
        #expect(Block.callout(id: UUID(), kind: .note, title: "Titled", body: "").isEmpty == false)
        #expect(Block.callout(id: UUID(), kind: .note, title: "", body: "Body").isEmpty == false)
    }

    @Test("Title and body are both searchable")
    func searchableTexts() {
        let block = Block.callout(id: UUID(), kind: .tip, title: "Heading", body: "Body")
        #expect(block.searchableTexts == ["Heading", "Body"])
        #expect(Block.callout(id: UUID(), kind: .tip, title: "", body: "Body").searchableTexts == ["Body"])
    }

    @Test("Callouts differing only in kind or title are not equal")
    func equality() {
        let id = UUID()
        let note = Block.callout(id: id, kind: .note, title: "T", body: "B")
        #expect(note == Block.callout(id: id, kind: .note, title: "T", body: "B"))
        #expect(note != Block.callout(id: id, kind: .tip, title: "T", body: "B"))
        #expect(note != Block.callout(id: id, kind: .note, title: "Other", body: "B"))
        #expect(note != Block.callout(id: id, kind: .note, title: "T", body: "Other"))
    }

    @Test("The factory makes an untitled note")
    func factory() {
        guard case let .callout(_, kind, title, body) = Block.emptyCallout() else {
            Issue.record("Expected a callout from the factory")
            return
        }
        #expect(kind == .note)
        #expect(title.isEmpty)
        #expect(body.isEmpty)
    }

    // MARK: - Kind metadata

    @Test("Unrecognised markers are not a kind")
    func unknownMarkerIsNotAKind() {
        #expect(CalloutKind(marker: "BANANA") == nil)
        #expect(CalloutKind(marker: "") == nil)
    }

    @Test("Every kind has a marker, a default title and a symbol")
    func kindMetadata() {
        for kind in CalloutKind.allCases {
            #expect(!kind.rawValue.isEmpty)
            #expect(!kind.defaultTitle.isEmpty)
            #expect(!kind.symbolName.isEmpty)
            #expect(CalloutKind(marker: kind.rawValue) == kind)
        }
    }

    // MARK: - Slash menu

    @Test("Callout is offered in the slash menu under Advanced")
    func slashMenuEntry() {
        #expect(BlockType.allCases.contains(.callout))
        #expect(BlockType.callout.category == .advanced)
        guard case let .callout(_, kind, title, body) = BlockType.callout.makeBlock(id: UUID(), text: "Carried") else {
            Issue.record("Expected the callout block type to make a callout")
            return
        }
        #expect(kind == .note)
        #expect(title.isEmpty)
        // Existing text becomes the body rather than the title.
        #expect(body == "Carried")
    }
}
