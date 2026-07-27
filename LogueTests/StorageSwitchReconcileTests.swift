import Foundation
@testable import Logue
import Testing

/// The two reconciliation rules that run when plain-markdown storage is turned off.
///
/// Both are pure functions extracted from `DocumentStore` for exactly this reason: one
/// decides which documents survive the switch, the other decides which files get deleted.
/// A mistake in either is silent data loss, and neither is observable from the UI until it
/// is too late.
@Suite("Storage switch reconciliation")
struct StorageSwitchReconcileTests {
    private func document(_ title: String, trashed: Bool = false) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.isTrashed = trashed
        return doc
    }

    // MARK: - Merging imported documents with the encrypted trash

    @Test("Documents read from the folder are kept")
    func keepsImported() {
        let imported = [document("Alpha"), document("Beta")]
        let merged = DocumentStore.merging(imported: imported, carryingTrashFrom: [])

        #expect(merged.count == 2)
    }

    /// Trash has no file in the folder, so without this it would vanish on the round trip.
    @Test("Trashed documents are carried over from encrypted storage")
    func carriesTrash() throws {
        let trashed = document("Deleted", trashed: true)
        let merged = DocumentStore.merging(
            imported: [document("Alpha")], carryingTrashFrom: [trashed]
        )

        #expect(merged.count == 2)
        let restored = try #require(merged.first { $0.id == trashed.id })
        #expect(restored.isTrashed)
    }

    /// The other half of the rule: a document the user deleted *outside* the app must not
    /// come back from its stale encrypted copy.
    @Test("A non-trashed document missing from the folder is not resurrected")
    func doesNotResurrectDeleted() {
        let removedOutsideTheApp = document("Gone")
        let merged = DocumentStore.merging(
            imported: [document("Alpha")], carryingTrashFrom: [removedOutsideTheApp]
        )

        #expect(merged.count == 1)
        #expect(merged.contains { $0.id == removedOutsideTheApp.id } == false)
    }

    @Test("A document present in both is taken from the folder, not the encrypted copy")
    func importedWinsOnCollision() throws {
        var edited = document("Edited outside")
        let stale = edited
        edited.body = "new text"
        var staleTrashed = stale
        staleTrashed.isTrashed = true

        let merged = DocumentStore.merging(
            imported: [edited], carryingTrashFrom: [staleTrashed]
        )

        #expect(merged.count == 1)
        let survivor = try #require(merged.first)
        #expect(survivor.body == "new text")
        #expect(survivor.isTrashed == false)
    }

    @Test("An empty folder still restores the trash")
    func emptyFolderKeepsTrash() {
        let merged = DocumentStore.merging(
            imported: [], carryingTrashFrom: [document("Deleted", trashed: true)]
        )
        #expect(merged.count == 1)
    }

    // MARK: - Choosing which encrypted files to delete

    @Test("A file whose document is gone is stale")
    func findsStaleFile() {
        let gone = UUID()
        let files = [URL.temporaryDirectory.appendingPathComponent("\(gone.uuidString).json")]

        #expect(DocumentStore.staleDocumentFiles(among: files, keeping: []) == files)
    }

    @Test("A file whose document is still live is kept")
    func keepsLiveFile() {
        let live = UUID()
        let files = [URL.temporaryDirectory.appendingPathComponent("\(live.uuidString).json")]

        #expect(DocumentStore.staleDocumentFiles(among: files, keeping: [live]).isEmpty)
    }

    /// Anything we do not recognise is somebody else's file. Deleting it would be the worst
    /// possible outcome of a storage toggle.
    @Test("Files that are not ours are never selected for deletion")
    func ignoresForeignFiles() {
        let files = [
            URL.temporaryDirectory.appendingPathComponent("notes.txt"),
            URL.temporaryDirectory.appendingPathComponent("settings.json"),
            URL.temporaryDirectory.appendingPathComponent("index.sqlite"),
        ]

        #expect(DocumentStore.staleDocumentFiles(among: files, keeping: []).isEmpty)
    }

    @Test("An empty directory yields nothing to delete")
    func handlesEmptyDirectory() {
        #expect(DocumentStore.staleDocumentFiles(among: [], keeping: [UUID()]).isEmpty)
    }
}
