import Foundation
@testable import Logue
import Testing

@Suite("MirrorImportPlan")
struct MirrorImportPlanTests {
    private let knownID = UUID()

    @Test("A file with no identifier is imported as a new document")
    func newFileImported() {
        let plan = MirrorImportPlan.plan(
            fileContents: "---\ntitle: Nested Doc\n---\nbody here\n",
            filename: "nested.md",
            knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "Nested Doc", body: "body here\n", tags: []))
    }

    @Test("A file with no frontmatter at all is imported, titled from its filename")
    func plainFileImported() {
        let plan = MirrorImportPlan.plan(
            fileContents: "just prose",
            filename: "Meeting Notes.md",
            knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "Meeting Notes", body: "just prose", tags: []))
    }

    @Test("An explicit title wins over the filename")
    func explicitTitleWins() {
        let plan = MirrorImportPlan.plan(
            fileContents: "---\ntitle: Real Title\n---\nbody",
            filename: "whatever.md",
            knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "Real Title", body: "body", tags: []))
    }

    @Test("A blank title falls back to the filename")
    func blankTitleFallsBack() {
        let plan = MirrorImportPlan.plan(
            fileContents: "---\ntitle: \"   \"\n---\nbody",
            filename: "From File.md",
            knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "From File", body: "body", tags: []))
    }

    @Test("Tags are carried in on import")
    func tagsImported() {
        let plan = MirrorImportPlan.plan(
            fileContents: "---\ntitle: A\ntags:\n  - urgent\n  - later\n---\nbody",
            filename: "a.md",
            knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "A", body: "body", tags: ["urgent", "later"]))
    }

    @Test("A file for a known document is left to the normal sync path")
    func knownDocumentIsExisting() {
        let contents = "---\n\(MirrorFile.identifierKey): \(knownID.uuidString)\ntitle: A\n---\nbody"
        let plan = MirrorImportPlan.plan(
            fileContents: contents, filename: "a.md", knownDocumentIDs: [knownID]
        )
        #expect(plan == .existing(documentID: knownID))
    }

    /// The subtle rule: a file whose document was deleted in the app must not be
    /// silently brought back.
    @Test("A file whose identifier matches no document is ignored, not re-imported")
    func unknownIdentifierIgnored() {
        let orphanID = UUID()
        let contents = "---\n\(MirrorFile.identifierKey): \(orphanID.uuidString)\ntitle: A\n---\nbody"
        let plan = MirrorImportPlan.plan(
            fileContents: contents, filename: "a.md", knownDocumentIDs: [knownID]
        )
        #expect(plan == .ignoreUnknownIdentifier(orphanID))
    }

    @Test("A malformed identifier is treated as absent, so the file is imported")
    func malformedIdentifierImported() {
        let plan = MirrorImportPlan.plan(
            fileContents: "---\n\(MirrorFile.identifierKey): not-a-uuid\ntitle: A\n---\nbody",
            filename: "a.md",
            knownDocumentIDs: [knownID]
        )
        #expect(plan == .importAsNew(title: "A", body: "body", tags: []))
    }

    @Test("An empty file is imported with its filename as the title")
    func emptyFileImported() {
        let plan = MirrorImportPlan.plan(
            fileContents: "", filename: "Empty.md", knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "Empty", body: "", tags: []))
    }

    @Test("A unicode filename becomes a unicode title")
    func unicodeFilename() {
        let plan = MirrorImportPlan.plan(
            fileContents: "body", filename: "会議メモ.md", knownDocumentIDs: []
        )
        #expect(plan == .importAsNew(title: "会議メモ", body: "body", tags: []))
    }

    @Test("A filename of only an extension still yields a usable title")
    func extensionOnlyFilename() {
        guard case let .importAsNew(title, _, _) = MirrorImportPlan.plan(
            fileContents: "body", filename: ".md", knownDocumentIDs: []
        )
        else {
            Issue.record("Expected an import")
            return
        }
        #expect(title.isEmpty == false)
    }
}
