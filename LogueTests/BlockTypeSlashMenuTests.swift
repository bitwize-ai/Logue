import Foundation
@testable import Logue
import Testing

/// The slash menu is driven entirely off `BlockType.allCases`, so a new block type
/// is only reachable once it appears there with complete metadata.
@Suite("BlockTypeSlashMenu")
struct BlockTypeSlashMenuTests {
    @Test("Diagram and equation are offered in the slash menu")
    func newTypesAreListed() {
        #expect(BlockType.allCases.contains(.mermaid))
        #expect(BlockType.allCases.contains(.math))
    }

    @Test("Every block type has non-empty menu metadata")
    func allTypesHaveMetadata() {
        for type in BlockType.allCases {
            #expect(!type.displayName.isEmpty, "\(type) has no display name")
            #expect(!type.iconName.isEmpty, "\(type) has no icon")
            #expect(!type.description.isEmpty, "\(type) has no description")
        }
    }

    @Test("Diagram and equation are grouped under Advanced")
    func newTypesAreAdvanced() {
        #expect(BlockType.mermaid.category == .advanced)
        #expect(BlockType.math.category == .advanced)
    }

    @Test("Every block type appears in exactly one category group")
    func groupingCoversEveryType() {
        let grouped = BlockType.groupedByCategory.flatMap(\.types)
        #expect(grouped.count == BlockType.allCases.count)
        #expect(Set(grouped) == Set(BlockType.allCases))
    }

    @Test("Filtering by name finds the diagram block")
    func filteringFindsDiagram() {
        let matches = BlockType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains("diagram")
        }
        #expect(matches.contains(.mermaid))
    }

    @Test("Each new type maps to its matching block case")
    func typesMapToBlocks() {
        guard case .mermaid = BlockType.mermaid.makeBlock(id: UUID(), text: "") else {
            Issue.record("mermaid BlockType did not produce a mermaid block")
            return
        }
        guard case .math = BlockType.math.makeBlock(id: UUID(), text: "") else {
            Issue.record("math BlockType did not produce a math block")
            return
        }
    }

    @Test("Existing text carries into the new block's source")
    func existingTextIsCarriedOver() {
        guard case let .math(_, latex) = BlockType.math.makeBlock(id: UUID(), text: "x = 1") else {
            Issue.record("Expected a math block")
            return
        }
        #expect(latex == "x = 1")
    }

    @Test("A new diagram block starts from a usable template, not empty")
    func diagramStartsFromTemplate() {
        guard case let .mermaid(_, source) = BlockType.mermaid.makeBlock(id: UUID(), text: "") else {
            Issue.record("Expected a mermaid block")
            return
        }
        #expect(source.contains("-->"))
    }
}
