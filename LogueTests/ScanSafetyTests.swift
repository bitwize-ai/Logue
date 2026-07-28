import Foundation
@testable import Logue
import Testing

/// The reasons a scan must not conclude that a document was deleted.
///
/// Every one of these came out of review, and they share a single cause: "absent from the walk" was
/// treated as "deleted". A symlinked root, an unreadable directory, a file caught mid-write and a
/// document moved while the walk was in flight all produce absence, and none of them is a deletion.
@Suite("Scan safety")
struct ScanSafetyTests {
    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-safety-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.path
        )
        try? FileManager.default.removeItem(at: url)
    }

    private func document(_ title: String) -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = "body"
        return doc.content
    }

    // MARK: - The cross-check

    @Test("A document whose file is still on disk is never trashed, however the walk went")
    func fileOnDiskIsNeverTrashed() {
        let doc = document("Alpha")

        let plan = ExternalChangePlanner.plan(scanned: [], known: [doc], stillOnDisk: [doc.id])

        #expect(plan.trashed.isEmpty)
        #expect(plan.unwalkable == [doc.id])
    }

    @Test("A document whose file is genuinely gone is still trashed")
    func missingFileIsStillTrashed() {
        let doc = document("Alpha")

        let plan = ExternalChangePlanner.plan(scanned: [], known: [doc], stillOnDisk: [])

        #expect(plan.trashed == [doc.id])
    }

    // MARK: - A root that cannot be walked

    /// Reproduced on APFS by the reviewer: `fileExists` follows a symlink and succeeds while
    /// `enumerator(at:)` does *not* follow it and yields nothing — so the folder read as present and
    /// empty, and empty meant "every document was deleted".
    ///
    /// The fix resolves the link rather than refusing it, because pointing this folder at a vault or
    /// a synced directory is the most obvious use of the feature. So the assertion is that a
    /// symlinked root *works*.
    @Test("A symlinked root is walked, not read as empty")
    func symlinkedRootIsWalked() throws {
        let real = temporaryRoot()
        defer { cleanUp(real) }
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: link) }

        var doc = WritingDocument()
        doc.title = "Alpha"
        doc.body = "text"
        #expect(MarkdownStorageMigrator(rootURL: real).export(documents: [doc.content], spaces: []).isSuccess)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let scan = MarkdownFolderScan(rootURL: link, adoptionSettleSeconds: 0)
        #expect(scan.isRootPresent)

        // The document is found through the link, so nothing is trashed.
        let plan = scan.plan(spaces: [], known: [doc.content])
        #expect(plan.trashed.isEmpty)
        #expect(plan.isEmpty)
    }

    @Test("A scan against an unwalkable root plans nothing")
    func unwalkableRootPlansNothing() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try "text".write(to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        let plan = scan.plan(spaces: [], known: [document("Alpha")])

        #expect(plan.isEmpty)
        #expect(plan.trashed.isEmpty)
    }

    @Test("A walk reports whether it completed")
    func walkReportsCompleteness() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try "text".write(to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        #expect(MarkdownStorageMigrator(rootURL: root).walk().isComplete)

        let blocked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }

        #expect(MarkdownStorageMigrator(rootURL: root).walk().isComplete == false)
    }

    // MARK: - A file caught mid-write

    /// A truncated file is indistinguishable from one with no identifier, and adopting it wrote our
    /// frontmatter over content the user was still saving — while the same pass trashed the document
    /// that file was.
    @Test("A file written moments ago is not adopted")
    func freshFileIsNotAdopted() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try "partial cont".write(
            to: root.appendingPathComponent("in-flight.md"), atomically: true, encoding: .utf8
        )

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 60)
        let plan = scan.plan(spaces: [], known: [])

        #expect(plan.inserted.isEmpty)
    }

    @Test("A file that has settled is adopted")
    func settledFileIsAdopted() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try "finished".write(
            to: root.appendingPathComponent("settled.md"), atomically: true, encoding: .utf8
        )

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.plan(spaces: [], known: []).inserted.count == 1)
    }

    @Test("An in-flight file leaves its own content alone")
    func freshFileIsNotOverwritten() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        let url = root.appendingPathComponent("in-flight.md")
        try "partial cont".write(to: url, atomically: true, encoding: .utf8)

        _ = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 60).plan(spaces: [], known: [])

        #expect(try String(contentsOf: url, encoding: .utf8) == "partial cont")
    }

    // MARK: - Filenames the filesystem folds together

    /// Reproduced on APFS by the reviewer: two titles differing only in case resolved to names the
    /// case-sensitive `taken` set did not contain, so the second write replaced the first file.
    @Test("Titles differing only in case get different files")
    func caseOnlyTitlesDoNotCollide() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var upper = WritingDocument()
        upper.title = "Notes"
        upper.body = "the first document"
        var lower = WritingDocument()
        lower.title = "notes"
        lower.body = "the second document"

        let migrator = MarkdownStorageMigrator(rootURL: root)
        let result = migrator.export(documents: [upper.content, lower.content], spaces: [])

        #expect(result.isSuccess)
        #expect(result.writtenFiles.count == 2)

        let files = migrator.markdownFiles()
            .filter { !SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
        #expect(files.count == 2)

        // And neither document lost its text to the other.
        let bodies = Set(files.compactMap { url -> String? in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return MarkdownDocumentFile.content(from: contents)?.body
        })
        #expect(bodies == ["the first document", "the second document"])
    }

    @Test("A filename already taken in another case is avoided")
    func filenameAvoidsCaseVariant() {
        var doc = WritingDocument()
        doc.title = "Notes"

        let name = DocumentFilename.filename(for: doc, avoiding: ["notes.md"])

        #expect(name.lowercased() != "notes.md")
    }
}
