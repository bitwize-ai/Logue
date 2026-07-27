import Foundation
@testable import Logue
import Testing

@Suite("DocumentTypes")
struct DocumentTypeTests {
    // MARK: - Definition

    @Test("A type round-trips through persistence")
    func roundTrips() throws {
        let type = DocumentType(
            name: "Project",
            symbolName: "briefcase",
            colorName: "blue",
            sidebarOrder: 10,
            pinnedProperties: ["status"],
            defaultProperties: ["status": .text("Active")],
            template: "## Goal\n\n## Next steps"
        )
        let decoded = try JSONDecoder().decode(DocumentType.self, from: JSONEncoder().encode(type))
        #expect(decoded == type)
    }

    @Test("A type name is sanitised")
    func nameSanitised() {
        #expect(DocumentType(name: "  Project  ").name == "Project")
    }

    @Test("A blank name falls back rather than producing an unnamed type")
    func blankNameFallsBack() {
        #expect(DocumentType(name: "   ").name.isEmpty == false)
    }

    @Test("An over-long name is truncated")
    func longNameTruncated() {
        let type = DocumentType(name: String(repeating: "a", count: 200))
        #expect(type.name.count <= DocumentType.maxNameLength)
    }

    @Test("Control characters are stripped from the name")
    func controlCharactersStripped() {
        #expect(DocumentType(name: "Pro\nject").name == "Project")
    }

    @Test("A type has sensible defaults")
    func defaults() {
        let type = DocumentType(name: "Note")
        #expect(type.symbolName.isEmpty == false)
        #expect(type.pinnedProperties.isEmpty)
        #expect(type.template == nil)
    }

    // MARK: - Applying to a document

    @Test("Applying a type sets the type property")
    func appliesTypeProperty() {
        let type = DocumentType(name: "Project")
        let doc = type.applied(to: WritingDocument())
        #expect(doc.property(PropertyKey.type.rawValue) == .text("Project"))
    }

    @Test("Applying a type seeds its default properties")
    func seedsDefaultProperties() {
        let type = DocumentType(name: "Project", defaultProperties: ["status": .text("Active")])
        let doc = type.applied(to: WritingDocument())
        #expect(doc.property("status") == .text("Active"))
    }

    @Test("Applying a type does not overwrite a property the document already has")
    func doesNotOverwriteExisting() {
        var doc = WritingDocument()
        doc.setProperty("status", value: .text("Done"))

        let type = DocumentType(name: "Project", defaultProperties: ["status": .text("Active")])
        let updated = type.applied(to: doc)

        #expect(updated.property("status") == .text("Done"))
    }

    @Test("Applying a type seeds the template into an empty document body")
    func seedsTemplateIntoEmptyBody() {
        let type = DocumentType(name: "Project", template: "## Goal")
        let doc = type.applied(to: WritingDocument())
        #expect(doc.body == "## Goal")
    }

    @Test("Applying a type never overwrites existing body content")
    func neverOverwritesBody() {
        var doc = WritingDocument()
        doc.body = "my own words"

        let type = DocumentType(name: "Project", template: "## Goal")
        #expect(type.applied(to: doc).body == "my own words")
    }

    @Test("A document's type is readable back")
    func typeReadableFromDocument() {
        let doc = DocumentType(name: "Project").applied(to: WritingDocument())
        #expect(doc.typeName == "Project")
    }

    @Test("A document with no type property has no type name")
    func noTypeName() {
        #expect(WritingDocument().typeName == nil)
    }

    // MARK: - Registry

    @Test("Types are listed in sidebar order, then by name")
    func sidebarOrdering() {
        let types = [
            DocumentType(name: "Zeta", sidebarOrder: 1),
            DocumentType(name: "Alpha", sidebarOrder: 2),
            DocumentType(name: "Beta", sidebarOrder: 1),
        ]
        #expect(DocumentType.ordered(types).map(\.name) == ["Beta", "Zeta", "Alpha"])
    }

    @Test("A type can be found by name, case-insensitively")
    func findByName() {
        let types = [DocumentType(name: "Project"), DocumentType(name: "Person")]
        #expect(DocumentType.matching(name: "project", in: types)?.name == "Project")
    }

    @Test("An unknown name finds nothing")
    func unknownName() {
        #expect(DocumentType.matching(name: "nope", in: []) == nil)
    }

    @Test("Documents can be grouped by their type")
    func groupingByType() {
        let project = DocumentType(name: "Project")
        let documents = [
            project.applied(to: WritingDocument()),
            project.applied(to: WritingDocument()),
            WritingDocument(),
        ]
        let grouped = DocumentType.grouped(documents)
        #expect(grouped["Project"]?.count == 2)
        #expect(grouped[DocumentType.untypedGroupName]?.count == 1)
    }
}
