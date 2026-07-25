import Foundation
@testable import Logue
import Testing

/// Mermaid and math blocks must be durable in the markdown file, not editor-only
/// state — otherwise reopening a document loses the diagram.
@Suite("DiagramAndMathBlocks")
struct DiagramMathBlockTests {
    // MARK: - Mermaid

    @Test("A mermaid fence parses into a mermaid block, not a code block")
    func mermaidFenceParsesAsMermaidBlock() {
        let markdown = """
        ```mermaid
        flowchart LR
          A --> B
        ```
        """
        let blocks = BlockSerializer.parse(markdown: markdown)

        #expect(blocks.count == 1)
        guard case let .mermaid(_, source) = blocks[0] else {
            Issue.record("Expected a mermaid block, got \(blocks[0])")
            return
        }
        #expect(source == "flowchart LR\n  A --> B")
    }

    @Test("A mermaid block serializes back to a mermaid fence")
    func mermaidRoundTrip() {
        let markdown = """
        ```mermaid
        flowchart LR
          A --> B
        ```
        """
        let output = BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown))
        #expect(output == markdown)
    }

    @Test("A plain code fence is still a code block")
    func plainCodeFenceIsUnaffected() {
        let blocks = BlockSerializer.parse(markdown: "```swift\nlet x = 1\n```")
        guard case let .codeBlock(_, language, _) = blocks[0] else {
            Issue.record("Expected a code block, got \(blocks[0])")
            return
        }
        #expect(language == "swift")
    }

    // MARK: - Math

    @Test("A $$ fence parses into a math block")
    func dollarFenceParsesAsMathBlock() {
        let markdown = """
        $$
        E = mc^2
        $$
        """
        let blocks = BlockSerializer.parse(markdown: markdown)

        #expect(blocks.count == 1)
        guard case let .math(_, latex) = blocks[0] else {
            Issue.record("Expected a math block, got \(blocks[0])")
            return
        }
        #expect(latex == "E = mc^2")
    }

    @Test("A math block serializes back to a $$ fence")
    func mathRoundTrip() {
        let markdown = """
        $$
        \\frac{a}{b} = c
        $$
        """
        let output = BlockSerializer.serialize(blocks: BlockSerializer.parse(markdown: markdown))
        #expect(output == markdown)
    }

    @Test("Multi-line latex is preserved exactly")
    func multiLineLatexPreserved() {
        let latex = "a = b \\\\\nc = d"
        let block = Block.math(id: UUID(), latex: latex)
        let output = BlockSerializer.serialize(blocks: [block])
        let reparsed = BlockSerializer.parse(markdown: output)

        guard case let .math(_, roundTripped) = reparsed[0] else {
            Issue.record("Expected a math block, got \(reparsed[0])")
            return
        }
        #expect(roundTripped == latex)
    }

    // MARK: - Shared block behaviour

    @Test("Diagram and math blocks are not text blocks")
    func neitherIsATextBlock() {
        #expect(Block.mermaid(id: UUID(), source: "graph TD").isTextBlock == false)
        #expect(Block.math(id: UUID(), latex: "x").isTextBlock == false)
    }

    @Test("Empty source makes the block empty")
    func emptinessReflectsSource() {
        #expect(Block.mermaid(id: UUID(), source: "  ").isEmpty)
        #expect(Block.mermaid(id: UUID(), source: "graph TD").isEmpty == false)
        #expect(Block.math(id: UUID(), latex: "").isEmpty)
        #expect(Block.math(id: UUID(), latex: "x = 1").isEmpty == false)
    }

    @Test("Source text is searchable so document search can find diagrams")
    func sourceIsSearchable() {
        #expect(Block.mermaid(id: UUID(), source: "graph TD").searchableTexts == ["graph TD"])
        #expect(Block.math(id: UUID(), latex: "E = mc^2").searchableTexts == ["E = mc^2"])
    }
}
