import Foundation
@testable import Logue
import Testing

/// Folder shapes that used to be misread, each one a defect a review found.
///
/// These are the cases where the app's idea of where a folder should be and the folder's actual
/// place disagreed. Every one of them ended in a space being deleted and its documents trashed, so
/// they are grouped together: the shared lesson is that a folder's identity, not its name, decides
/// which space it is.
@Suite("Folder shapes that must not be misread")
struct MarkdownFolderMisreadTests {
    // MARK: - Harness

    /// Stands in for the stores: applies a scan the way the app does, so the sequencing under
    /// test is the real sequencing rather than a paraphrase of it.
    private struct Library {
        var spaces: [Space] = []
        var documents: [DocumentContent] = []

        mutating func apply(_ scan: MarkdownFolderScan) -> ExternalChangePlan {
            // Deletions first, exactly as the app orders them: a space whose folder is gone must
            // not be handed to adoption as a folder to recreate.
            let vanished = scan.vanishedSpaceIDs(in: spaces)
            if !vanished.isEmpty {
                var doomed = vanished
                for space in spaces where doomed.contains(space.parentID ?? space.id) {
                    doomed.insert(space.id)
                }
                spaces.removeAll { doomed.contains($0.id) }
                for index in documents.indices where doomed.contains(documents[index].spaceID ?? UUID()) {
                    documents[index].isTrashed = true
                }
            }

            for rename in scan.folderRenames(in: spaces) {
                guard let index = spaces.firstIndex(where: { $0.id == rename.id }) else { continue }
                spaces[index].name = rename.name
                spaces[index].parentID = SpaceFolderLayout.spaceID(
                    forDirectoryComponents: rename.parentComponents, in: spaces
                )
            }

            for creation in scan.spaceCreations(in: spaces) {
                let identity = scan.identity(forDirectoryComponents: creation.components)
                // The same decision the app makes, so this harness tests the real rule rather
                // than a paraphrase of it. Only the mutation differs from `SpaceStore`.
                let parentID = SpaceFolderLayout.spaceID(
                    forDirectoryComponents: creation.parentComponents, in: spaces
                )
                // `SpaceStore.adoptSpace` returns the existing space when the identifier is already
                // known, so the harness must too — otherwise a folder claiming a space we have would
                // become a second space sharing its identity.
                let claimedID = identity?.id ?? UUID()
                if spaces.contains(where: { $0.id == claimedID }) {
                    continue
                }
                let adopted = Space(id: claimedID, name: creation.name, parentID: parentID)
                spaces.append(adopted)
                // At the folder's known path, exactly as the app does — a name the app would spell
                // differently cannot be turned back into the path it came from.
                scan.writeSpaceIdentity(for: adopted, atComponents: creation.components)
            }
            scan.writeSpaceIdentities(spaces: spaces)

            let plan = scan.plan(spaces: spaces, known: documents)

            for content in plan.updated {
                guard let index = documents.firstIndex(where: { $0.id == content.id }) else { continue }
                documents[index] = content
            }
            documents.append(contentsOf: plan.inserted)
            for id in plan.trashed {
                guard let index = documents.firstIndex(where: { $0.id == id }) else { continue }
                documents[index].isTrashed = true
            }
            return plan
        }
    }

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Folder names the app would spell differently

    /// A folder named in a way the app sanitises — a leading dash, here — used to have a space whose
    /// expected path was `Work` while its folder was `-Work`. Nothing matched: no `_space.md` was
    /// written, the next scan read the space as folderless and deleted it, and the one after created
    /// it again with a new identity. The sidebar flickered and documents inside never filed.
    @Test("A folder whose name the app would sanitise keeps one stable space")
    func sanitisedNameKeepsStableSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("-Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)

        let firstID = try #require(library.spaces.first?.id)
        #expect(library.spaces.count == 1)

        _ = library.apply(scan)
        _ = library.apply(scan)

        #expect(library.spaces.count == 1)
        #expect(library.spaces.first?.id == firstID)
        #expect(library.documents.first?.isTrashed == false)
    }

    @Test("A document in such a folder is filed into its space")
    func sanitisedNameFilesDocuments() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("-Work/plan.md"))

        var library = Library()
        _ = library.apply(MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0))

        #expect(library.documents.first?.spaceID == library.spaces.first?.id)
    }

    /// A name longer than the filename budget is the same class of problem.
    @Test("A very long folder name keeps one stable space")
    func longNameKeepsStableSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let longName = String(repeating: "Project ", count: 12)
        try write("text", to: root.appendingPathComponent("\(longName)/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)
        let firstID = try #require(library.spaces.first?.id)

        _ = library.apply(scan)

        #expect(library.spaces.count == 1)
        #expect(library.spaces.first?.id == firstID)
    }

    // MARK: - A folder duplicated in Finder

    /// Both copies carry the same `_logue_space_id`. Only one resolved by name, so the other was read
    /// as a rename — and the next scan read the first one that way, so the space's name alternated
    /// between the two folder names for as long as both existed.
    @Test("Duplicating a space folder does not make its name alternate")
    func duplicatedFolderDoesNotPingPong() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)
        #expect(library.spaces.map(\.name) == ["Work"])

        try FileManager.default.copyItem(
            at: root.appendingPathComponent("Work"), to: root.appendingPathComponent("Work copy")
        )

        var names: Set<String> = []
        for _ in 0 ..< 4 {
            _ = library.apply(scan)
            names.insert(library.spaces.first?.name ?? "")
        }

        #expect(names == ["Work"])
        #expect(library.spaces.count == 1)
    }

    @Test("A duplicated space folder is reported")
    func duplicatedFolderIsReported() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))
        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)

        try FileManager.default.copyItem(
            at: root.appendingPathComponent("Work"), to: root.appendingPathComponent("Work copy")
        )

        #expect(scan.duplicatedSpaceFolders(in: library.spaces) == [["Work copy"]])
    }

    /// A duplicated *file* carries a duplicated document identifier. Two passes each pick "the first
    /// file with this identifier", and if they ever disagree the losing copy reads as an outside edit
    /// and overwrites the user's current text. Sorted enumeration makes the choice the same everywhere.
    @Test("A duplicated document file is reported and does not change the document")
    func duplicatedFileIsReportedAndInert() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var doc = WritingDocument()
        doc.title = "Alpha"
        doc.body = "current text"
        let migrator = MarkdownStorageMigrator(rootURL: root)
        let url = try #require(migrator.export(documents: [doc.content], spaces: []).writtenFiles[doc.id])

        // The copy holds older text, as a duplicate made before an edit would.
        let stale = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "current text", with: "stale text")
        try stale.write(to: root.appendingPathComponent("Alpha copy.md"), atomically: true, encoding: .utf8)

        var library = Library(spaces: [], documents: [doc.content])
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)

        #expect(library.apply(scan).isEmpty)
        #expect(library.apply(scan).isEmpty)
        #expect(library.documents.first?.body == "current text")
        #expect(scan.duplicatedDocumentFiles().count == 1)
    }

    // MARK: - Reasons a living folder must never read as deleted

    /// The worst defect a review found. Deleting `_space.md` in Finder made the space read as gone,
    /// which deleted the space, trashed its documents, and — because trashing a document in this
    /// mode removes its file — erased every `.md` in a folder the user was looking at.
    @Test("Deleting a folder's space file does not delete the space")
    func deletedSpaceFileKeepsSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)
        #expect(library.spaces.count == 1)

        try FileManager.default.removeItem(
            at: root.appendingPathComponent("Work/\(SpaceFile.filename)")
        )
        _ = library.apply(scan)

        #expect(library.spaces.count == 1)
        #expect(library.documents.first?.isTrashed == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/plan.md").path))
    }

    @Test("A corrupt identifier in a space file does not delete the space")
    func corruptSpaceFileKeepsSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        _ = library.apply(scan)

        try "---\n_logue_space_id: not-a-uuid\n---\n".write(
            to: root.appendingPathComponent("Work/\(SpaceFile.filename)"),
            atomically: true,
            encoding: .utf8
        )
        _ = library.apply(scan)

        #expect(library.spaces.count == 1)
        #expect(library.documents.first?.isTrashed == false)
    }

    /// A space whose identity file was never written — a failed write, or a quit between adopting
    /// the folder and writing to it — must not delete itself on the next launch.
    @Test("A folder with no space file at all keeps its space")
    func missingSpaceFileKeepsSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Work"), withIntermediateDirectories: true
        )

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.vanishedSpaceIDs(in: [work]).isEmpty)
    }

    /// A file naming a trashed document is an orphan, not an edit. Reading it as an update cleared
    /// `isTrashed`, so a document came back out of the trash by itself.
    @Test("A file naming a trashed document does not restore it")
    func fileForTrashedDocumentDoesNotRestoreIt() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var doc = WritingDocument()
        doc.title = "Deleted"
        doc.body = "text"
        let migrator = MarkdownStorageMigrator(rootURL: root)
        #expect(migrator.export(documents: [doc.content], spaces: []).isSuccess)

        // The document is trashed in the app but its file is still there — a failed removal, or the
        // user put it back from their Trash.
        var trashed = doc.content
        trashed.isTrashed = true

        var library = Library(spaces: [], documents: [trashed])
        let plan = library.apply(MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0))

        #expect(plan.updated.isEmpty)
        #expect(library.documents.first?.isTrashed == true)
    }

    // MARK: - What actually stops the write/read loop

    /// The property that matters, stated without reference to any one mechanism: after the app
    /// writes, a scan of the same folder has nothing to say.
    ///
    /// This is the loop that would cost keystrokes — write, event, read, apply, write — and it is
    /// broken by the diff coming out empty, not by recognising our own events. An earlier version
    /// had a content-hash filter for that job whose `isEcho` was never called from anywhere;
    /// deleting it changed no behaviour, which is exactly why a test naming a mechanism is worth
    /// less than a test naming the outcome.
    @Test("A scan straight after the app writes produces no work, however many times it runs")
    func writeThenScanIsQuiet() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var doc = WritingDocument()
        doc.title = "Written by Logue"
        doc.body = "text\n\nwith a blank line\n"

        let work = Space(name: "Work")
        doc.spaceID = work.id
        let migrator = MarkdownStorageMigrator(rootURL: root)
        migrator.createSpaceFolders(spaces: [work])
        #expect(migrator.export(documents: [doc.content], spaces: [work]).isSuccess)

        var library = Library(spaces: [work], documents: [doc.content])
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)

        #expect(library.apply(scan).isEmpty)
        #expect(library.apply(scan).isEmpty)
        #expect(library.spaces.count == 1)
        #expect(library.documents.count == 1)
    }

    /// And the other half: a genuine outside edit still gets through.
    @Test("An outside edit after our own write is still noticed")
    func outsideEditAfterOurWriteIsNoticed() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var doc = WritingDocument()
        doc.title = "Alpha"
        doc.body = "ours"

        let migrator = MarkdownStorageMigrator(rootURL: root)
        let url = try #require(migrator.export(documents: [doc.content], spaces: []).writtenFiles[doc.id])

        var library = Library(spaces: [], documents: [doc.content])
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(library.apply(scan).isEmpty)

        try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "ours", with: "theirs")
            .write(to: url, atomically: true, encoding: .utf8)

        #expect(library.apply(scan).updated.count == 1)
    }
}
