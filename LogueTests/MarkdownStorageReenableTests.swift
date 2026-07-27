import Foundation
@testable import Logue
import Testing

/// Turning plain markdown storage back on when a folder from a previous session is still there.
///
/// This is the case the user hits by turning the setting off, working for a while, and turning
/// it on again. Every test here is a way the leftover folder can undo work done while it was
/// off — silently, because the folder looks plausible either way.
@Suite("Re-enabling markdown storage")
struct MarkdownStorageReenableTests {
    // MARK: - Harness

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-reenable-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func document(_ title: String, body: String = "body") -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        return doc.content
    }

    /// Retires by deleting rather than trashing, so a test run does not put files in the
    /// user's Trash. What is under test is *which* files are retired, not how.
    private func migrator(_ root: URL) -> MarkdownStorageMigrator {
        MarkdownStorageMigrator(
            rootURL: root,
            retireFile: { try FileManager.default.removeItem(at: $0) }
        )
    }

    private func documentFiles(_ migrator: MarkdownStorageMigrator) -> [URL] {
        migrator.markdownFiles().filter { !SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
    }

    // MARK: - The duplicate

    /// The bug this suite was written for: a second file for the same document. Both carry the
    /// same identifier, so the next scan picks one arbitrarily — and if it picks the leftover,
    /// the user watches old text replace their work.
    @Test("Re-enabling writes into the file a document already has, not a second copy")
    func doesNotDuplicateFiles() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        var doc = document("Alpha", body: "first version")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)

        // Turned off, edited in the app, turned back on.
        doc.body = "version written while the setting was off"
        let result = migrator.reconcile(documents: [doc], spaces: [])

        #expect(result.isSuccess)
        #expect(documentFiles(migrator).count == 1)

        let url = try #require(documentFiles(migrator).first)
        let onDisk = try #require(MarkdownDocumentFile.content(from: String(contentsOf: url, encoding: .utf8)))
        #expect(onDisk.body == "version written while the setting was off")
    }

    @Test("A file the user renamed keeps its name across a re-enable")
    func keepsUserFilename() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        var doc = document("Alpha")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)
        let original = try #require(migrator.fileIndex()[doc.id])
        try FileManager.default.moveItem(at: original, to: root.appendingPathComponent("my name.md"))

        doc.body = "edited"
        #expect(migrator.reconcile(documents: [doc], spaces: []).isSuccess)

        #expect(documentFiles(migrator).map(\.lastPathComponent) == ["my name.md"])
    }

    // MARK: - Deletions made while the setting was off

    /// Without this, a document deleted while the setting was off comes back: its leftover file
    /// still names it, so the first scan reads the file as an edit and undoes the deletion.
    @Test("A file whose document was deleted while off is retired, not left to resurrect it")
    func retiresOrphanFile() {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        let deleted = document("Deleted while off")
        let kept = document("Kept")
        #expect(migrator.export(documents: [deleted, kept], spaces: []).isSuccess)

        let result = migrator.reconcile(documents: [kept], spaces: [])

        #expect(result.retiredFiles.count == 1)
        #expect(documentFiles(migrator).count == 1)
    }

    @Test("A file whose document is now in the trash is retired")
    func retiresTrashedDocumentFile() {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        var doc = document("Trashed while off")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)

        doc.isTrashed = true
        let result = migrator.reconcile(documents: [doc], spaces: [])

        #expect(result.retiredFiles.count == 1)
        #expect(documentFiles(migrator).isEmpty)
    }

    // MARK: - Edits made to the folder while the setting was off

    /// While the setting is off nothing watches the folder, so an edit there is invisible to the
    /// app and re-enabling has to overwrite it. Retiring the file first means the edit is
    /// recoverable from the Trash rather than gone.
    @Test("A file edited while off is retired before being replaced")
    func retiresDivergentFile() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        let doc = document("Alpha", body: "in the app")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)

        let url = try #require(migrator.fileIndex()[doc.id])
        let edited = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "in the app", with: "edited in another editor")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        let result = migrator.reconcile(documents: [doc], spaces: [])

        #expect(result.retiredFiles.count == 1)
        #expect(documentFiles(migrator).count == 1)
    }

    /// A file that already matches is left alone — nothing to preserve, so nothing goes to the
    /// Trash. Otherwise every re-enable would fill it with identical copies.
    @Test("A file that already matches its document is not retired")
    func leavesMatchingFileAlone() {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        let doc = document("Alpha")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)

        let result = migrator.reconcile(documents: [doc], spaces: [])

        #expect(result.retiredFiles.isEmpty)
        #expect(documentFiles(migrator).count == 1)
    }

    /// Someone else's markdown is not ours to retire. It has no identifier, so it is not a
    /// leftover of ours — it is a note they wrote, and the first scan adopts it.
    @Test("A file with no identifier is never retired")
    func neverRetiresUnidentifiedFiles() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        try "just prose".write(
            to: root.appendingPathComponent("handwritten.md"), atomically: true, encoding: .utf8
        )

        let result = migrator.reconcile(documents: [], spaces: [])

        #expect(result.retiredFiles.isEmpty)
        #expect(documentFiles(migrator).count == 1)
    }

    // MARK: - Spaces

    @Test("Re-enabling into an existing folder keeps documents in their space folders")
    func keepsSpacePlacement() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        let work = Space(name: "Work")
        var doc = document("Plan")
        doc.spaceID = work.id
        #expect(migrator.export(documents: [doc], spaces: [work]).isSuccess)

        doc.body = "edited while off"
        #expect(migrator.reconcile(documents: [doc], spaces: [work]).isSuccess)

        let url = try #require(documentFiles(migrator).first)
        #expect(url.path.contains("/Work/"))
        #expect(documentFiles(migrator).count == 1)
    }

    @Test("A first enable into an empty folder behaves like a plain export")
    func emptyFolderIsUnaffected() {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let migrator = migrator(root)

        let result = migrator.reconcile(documents: [document("Alpha")], spaces: [])

        #expect(result.isSuccess)
        #expect(result.retiredFiles.isEmpty)
        #expect(documentFiles(migrator).count == 1)
    }
}
