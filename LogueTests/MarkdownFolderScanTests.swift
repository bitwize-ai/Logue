import Foundation
@testable import Logue
import Testing

/// The whole chain, on a real folder: files and directories in, spaces and a plan out.
///
/// Every piece of this has its own tests, and that has not been enough before — three features
/// in this codebase shipped with each unit passing and the wiring between them broken. So these
/// tests drive the same entry points the app drives, in the same order, against a temporary
/// directory, and assert on what a user would notice.
@Suite("Markdown folder scan")
struct MarkdownFolderScanTests {
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

            for creation in scan.spaceCreations(in: spaces) {
                let identity = scan.identity(forDirectoryComponents: creation.components)
                // The same decision the app makes, so this harness tests the real rule rather
                // than a paraphrase of it. Only the mutation differs from `SpaceStore`.
                switch SpaceFolderAdoption.resolve(creation, claimedID: identity?.id, in: spaces) {
                case let .rename(id, name, parentComponents):
                    guard let index = spaces.firstIndex(where: { $0.id == id }) else { continue }
                    spaces[index].name = name
                    spaces[index].parentID = SpaceFolderLayout.spaceID(
                        forDirectoryComponents: parentComponents, in: spaces
                    )
                case let .create(id, name, parentComponents):
                    let parentID = SpaceFolderLayout.spaceID(
                        forDirectoryComponents: parentComponents, in: spaces
                    )
                    spaces.append(Space(id: id ?? UUID(), name: name, parentID: parentID))
                }
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

    // MARK: - Dropping in files

    @Test("A markdown file dropped in becomes a document")
    func adoptsDroppedFile() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("# Groceries\n\n- milk\n", to: root.appendingPathComponent("groceries.md"))

        var library = Library()
        let plan = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(plan.inserted.count == 1)
        #expect(library.documents.first?.body.contains("milk") == true)
    }

    /// The loop this codebase has to be proof against: scanning again must find nothing.
    @Test("Scanning twice does not import the same file twice")
    func repeatedScansAreQuiet() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("note.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        let second = library.apply(scan)
        let third = library.apply(scan)

        #expect(second.isEmpty)
        #expect(third.isEmpty)
        #expect(library.documents.count == 1)
    }

    @Test("A folder dropped in becomes a space, and files inside it are filed there")
    func adoptsFolderAndContents() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        _ = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(library.spaces.map(\.name) == ["Work"])
        #expect(library.documents.first?.spaceID == library.spaces.first?.id)
    }

    @Test("A nested tree becomes nested spaces")
    func adoptsNestedFolders() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/Projects/Q3/plan.md"))

        var library = Library()
        _ = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(library.spaces.count == 3)
        let leaf = try #require(library.spaces.first { $0.name == "Q3" })
        let middle = try #require(library.spaces.first { $0.name == "Projects" })
        #expect(leaf.parentID == middle.id)
        #expect(library.documents.first?.spaceID == leaf.id)
    }

    @Test("An empty folder still becomes a space")
    func adoptsEmptyFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Reading"), withIntermediateDirectories: true
        )

        var library = Library()
        _ = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(library.spaces.map(\.name) == ["Reading"])
    }

    // MARK: - Editing outside the app

    @Test("An edit made in another editor reaches the document")
    func externalEditIsApplied() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("note.md")
        try write("first draft", to: file)

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)

        // What another editor does: rewrite the body, leave the frontmatter alone.
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        try onDisk.replacingOccurrences(of: "first draft", with: "second draft").write(
            to: file, atomically: true, encoding: .utf8
        )

        let plan = library.apply(scan)
        #expect(plan.updated.count == 1)
        #expect(library.documents.first?.body.contains("second draft") == true)
    }

    @Test("Moving a file to another folder refiles the document")
    func externalMoveRefiles() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("note.md")
        try write("text", to: file)

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.documents.first?.spaceID == nil)

        let destination = root.appendingPathComponent("Work/note.md")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: file, to: destination)

        _ = library.apply(scan)
        let work = try #require(library.spaces.first { $0.name == "Work" })
        #expect(library.documents.first?.spaceID == work.id)
    }

    /// Renaming the file must not produce a second document, because the identifier inside it
    /// is what identifies it — not its name.
    @Test("Renaming a file outside the app keeps one document")
    func externalRenameKeepsOneDocument() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("note.md")
        try write("text", to: file)

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        let originalID = library.documents.first?.id

        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("renamed.md"))

        let plan = library.apply(scan)
        #expect(plan.inserted.isEmpty)
        #expect(plan.trashed.isEmpty)
        #expect(library.documents.count == 1)
        #expect(library.documents.first?.id == originalID)
    }

    @Test("Deleting a file outside the app trashes the document rather than losing it")
    func externalDeleteTrashes() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("note.md")
        try write("text", to: file)

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)

        try FileManager.default.removeItem(at: file)

        let plan = library.apply(scan)
        #expect(plan.trashed.count == 1)
        #expect(library.documents.first?.isTrashed == true)

        // And it stays trashed rather than being trashed again on every later scan.
        #expect(library.apply(scan).isEmpty)
    }

    // MARK: - Deleting folders outside the app

    /// The bug the user hit: a folder deleted in Finder came straight back, empty. `_space.md` was
    /// written for every space on every pass and created the directory as a side effect, so the
    /// deletion was undone within seconds — and undone empty, because the documents inside were
    /// correctly trashed.
    @Test("A folder deleted outside the app is not recreated")
    func deletedFolderStaysDeleted() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.spaces.count == 1)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work"))
        _ = library.apply(scan)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work").path) == false)
    }

    @Test("A folder deleted outside the app removes its space")
    func deletedFolderRemovesSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work"))
        _ = library.apply(scan)

        #expect(library.spaces.isEmpty)
    }

    /// The documents go to trash rather than disappearing: deleting a folder is easy to do by
    /// accident, and Logue's trash is the only place they can be got back from.
    @Test("Documents in a deleted folder are trashed, not lost")
    func deletedFolderTrashesDocuments() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work"))
        _ = library.apply(scan)

        #expect(library.documents.count == 1)
        #expect(library.documents.first?.isTrashed == true)
    }

    @Test("Deleting a parent folder removes its nested spaces too")
    func deletedParentRemovesChildren() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/Projects/Q3/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.spaces.count == 3)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work"))
        _ = library.apply(scan)

        #expect(library.spaces.isEmpty)
        #expect(library.documents.first?.isTrashed == true)
    }

    @Test("Deleting one folder leaves its siblings alone")
    func deletionIsScopedToOneFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))
        try write("text", to: root.appendingPathComponent("Personal/notes.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.spaces.count == 2)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work"))
        _ = library.apply(scan)

        #expect(library.spaces.map(\.name) == ["Personal"])
        #expect(library.documents.filter { !$0.isTrashed }.count == 1)
    }

    @Test("Deleting a nested folder keeps its parent")
    func deletingChildKeepsParent() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))
        try write("text", to: root.appendingPathComponent("Work/Projects/q3.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.spaces.count == 2)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Work/Projects"))
        _ = library.apply(scan)

        #expect(library.spaces.map(\.name) == ["Work"])
        #expect(library.documents.filter { !$0.isTrashed }.count == 1)
    }

    /// The catastrophic case. A folder on an unmounted volume, or one the user moved, or a sync
    /// that has not finished, all look exactly like "every folder was deleted".
    @Test("A missing root folder changes nothing at all")
    func missingRootIsIgnored() throws {
        let root = temporaryRoot()
        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        #expect(library.spaces.count == 1)

        try FileManager.default.removeItem(at: root)
        _ = library.apply(scan)

        #expect(scan.isRootPresent == false)
        #expect(library.spaces.count == 1)
        #expect(library.documents.filter { !$0.isTrashed }.count == 1)
    }

    /// Emptying a folder is not deleting it. The documents go, the space stays — otherwise
    /// clearing a folder out to refill it would take the space with it.
    @Test("Emptying a folder keeps the space and trashes only its documents")
    func emptiedFolderKeepsSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)

        let file = try #require(
            MarkdownStorageMigrator(rootURL: root).markdownFiles()
                .first { !SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
        )
        try FileManager.default.removeItem(at: file)
        _ = library.apply(scan)

        #expect(library.spaces.map(\.name) == ["Work"])
        #expect(library.documents.first?.isTrashed == true)
    }

    // MARK: - Our own writes

    /// The other half of the loop: a document saved by the app must read back as no change.
    @Test("A document written by the app produces no change when scanned")
    func ourOwnWriteIsQuiet() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var doc = WritingDocument()
        doc.title = "Written by Logue"
        doc.body = "text\n\nwith a blank line\n"

        let migrator = MarkdownStorageMigrator(rootURL: root)
        #expect(migrator.export(documents: [doc.content], spaces: []).isSuccess)

        var library = Library(spaces: [], documents: [doc.content])
        let plan = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(plan.isEmpty)
    }

    /// Saving an app-authored document while spaces exist writes `_space.md` files, which must
    /// not read as documents on the way back.
    @Test("Space files are never mistaken for documents")
    func spaceFilesAreNotDocuments() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        var doc = WritingDocument()
        doc.title = "Plan"
        doc.spaceID = work.id

        let migrator = MarkdownStorageMigrator(rootURL: root)
        #expect(migrator.export(documents: [doc.content], spaces: [work]).isSuccess)

        var library = Library(spaces: [work], documents: [doc.content])
        let plan = library.apply(MarkdownFolderScan(rootURL: root))

        #expect(plan.isEmpty)
        #expect(library.documents.count == 1)
    }

    /// A folder renamed in Finder is the same space, because `_space.md` says so. Without it
    /// the space would be replaced and lose its icon, colour and place in the sidebar.
    @Test("Renaming a folder keeps the same space")
    func renamedFolderKeepsIdentity() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try write("text", to: root.appendingPathComponent("Work/plan.md"))

        var library = Library()
        let scan = MarkdownFolderScan(rootURL: root)
        _ = library.apply(scan)
        let originalID = try #require(library.spaces.first?.id)

        try FileManager.default.moveItem(
            at: root.appendingPathComponent("Work"), to: root.appendingPathComponent("Client Work")
        )

        _ = library.apply(scan)
        #expect(library.spaces.count == 1)
        #expect(library.spaces.first?.id == originalID)
        #expect(library.spaces.first?.name == "Client Work")
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
        let scan = MarkdownFolderScan(rootURL: root)
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
        let scan = MarkdownFolderScan(rootURL: root)
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

        let scan = MarkdownFolderScan(rootURL: root)
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
        let plan = library.apply(MarkdownFolderScan(rootURL: root))

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
        let scan = MarkdownFolderScan(rootURL: root)

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
        let scan = MarkdownFolderScan(rootURL: root)
        #expect(library.apply(scan).isEmpty)

        try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "ours", with: "theirs")
            .write(to: url, atomically: true, encoding: .utf8)

        #expect(library.apply(scan).updated.count == 1)
    }
}
