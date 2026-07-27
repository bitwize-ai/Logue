import Foundation
@testable import Logue
import Testing

/// Migrating documents between encrypted storage and a plain-markdown folder.
///
/// Exercised against real temporary directories rather than mocks: this code's whole job
/// is filesystem behaviour, and the failure mode being guarded against — deleting the
/// encrypted originals after a bad write — only exists on a real filesystem.
@Suite("MarkdownStorageMigrator")
struct MarkdownStorageMigratorTests {
    // MARK: - Fixtures

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-migrator-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func document(_ title: String, space: UUID? = nil, body: String = "body") -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        doc.spaceID = space
        return doc.content
    }

    // MARK: - Export

    @Test("Every document is written as a file")
    func exportsAllDocuments() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let result = MarkdownStorageMigrator(rootURL: root).export(
            documents: [document("Alpha"), document("Beta")], spaces: []
        )

        #expect(result.isSuccess)
        #expect(result.writtenFiles.count == 2)
    }

    @Test("Documents are nested inside their space folders")
    func exportsNested() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let result = MarkdownStorageMigrator(rootURL: root).export(
            documents: [document("Notes", space: work.id)], spaces: [work]
        )

        #expect(result.isSuccess)
        let path = try #require(result.writtenFiles.values.first?.path)
        #expect(path.contains("/Work/"))
    }

    @Test("Each space folder gets a _space.md")
    func exportsSpaceFiles() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        _ = MarkdownStorageMigrator(rootURL: root).export(
            documents: [document("Notes", space: work.id)], spaces: [work]
        )

        let spaceFile = root.appendingPathComponent("Work/\(SpaceFile.filename)")
        #expect(FileManager.default.fileExists(atPath: spaceFile.path))
    }

    @Test("Export verifies what it wrote by reading it back")
    func exportVerifies() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let doc = document("Alpha", body: "important text")
        let migrator = MarkdownStorageMigrator(rootURL: root)
        let result = migrator.export(documents: [doc], spaces: [])

        let url = try #require(result.writtenFiles[doc.id])
        let contents = try String(contentsOf: url, encoding: .utf8)
        let readBack = try #require(MarkdownDocumentFile.content(from: contents))
        #expect(readBack.body == "important text")
    }

    /// The guard that matters: if verification cannot confirm a write, the caller must
    /// not go on to delete the encrypted original.
    @Test("A document that fails verification is reported as a failure, not a success")
    func exportReportsVerificationFailure() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        // A read-only directory makes the write fail without making the test lie about
        // what went wrong.
        let blocked = root.appendingPathComponent("blocked")
        try? FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: blocked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: blocked.path
            )
        }

        let result = MarkdownStorageMigrator(rootURL: blocked).export(
            documents: [document("Alpha")], spaces: []
        )

        #expect(result.isSuccess == false)
        #expect(result.failures.isEmpty == false)
    }

    @Test("An empty library exports successfully")
    func exportsEmptyLibrary() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let result = MarkdownStorageMigrator(rootURL: root).export(documents: [], spaces: [])
        #expect(result.isSuccess)
        #expect(result.writtenFiles.isEmpty)
    }

    @Test("Trashed documents are not written to the folder")
    func excludesTrashed() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var trashed = document("Gone")
        trashed.isTrashed = true

        let result = MarkdownStorageMigrator(rootURL: root).export(
            documents: [document("Alpha"), trashed], spaces: []
        )
        #expect(result.writtenFiles.count == 1)
    }

    // MARK: - Keeping the file a document already has

    /// The user is invited to rename these files. If a save picked a name from the title
    /// instead, their rename would come back as a second file next to the original.
    @Test("A renamed file keeps its name when the document is saved again")
    func reusesExistingFile() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let migrator = MarkdownStorageMigrator(rootURL: root)
        var doc = document("Alpha")
        #expect(migrator.export(documents: [doc], spaces: []).isSuccess)

        // Rename it the way the user would, in Finder.
        let original = try #require(migrator.fileIndex()[doc.id])
        let renamed = root.appendingPathComponent("my own name.md")
        try FileManager.default.moveItem(at: original, to: renamed)

        doc.body = "edited in the app"
        let result = migrator.export(documents: [doc], spaces: [], reusing: migrator.fileIndex())

        #expect(result.writtenFiles[doc.id]?.lastPathComponent == "my own name.md")
        #expect(migrator.markdownFiles().count == 1)
    }

    @Test("Moving a document between spaces moves its file and leaves nothing behind")
    func movesFileBetweenSpaces() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let migrator = MarkdownStorageMigrator(rootURL: root)
        var doc = document("Alpha")
        #expect(migrator.export(documents: [doc], spaces: [work]).isSuccess)

        doc.spaceID = work.id
        let result = migrator.export(documents: [doc], spaces: [work], reusing: migrator.fileIndex())

        let moved = try #require(result.writtenFiles[doc.id])
        #expect(moved.path.contains("/Work/"))

        let documentFiles = migrator.markdownFiles()
            .filter { !SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
        #expect(documentFiles.count == 1)
    }

    @Test("The file index maps each document to its file")
    func buildsFileIndex() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let first = document("Alpha")
        let second = document("Beta")
        let migrator = MarkdownStorageMigrator(rootURL: root)
        #expect(migrator.export(documents: [first, second], spaces: []).isSuccess)

        let index = migrator.fileIndex()
        #expect(index.count == 2)
        #expect(try #require(index[first.id]).lastPathComponent.contains("Alpha"))
    }

    // MARK: - Adopting a dropped-in file

    @Test("A markdown file dropped into the folder becomes a document")
    func adoptsDroppedFile() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("shopping list.md")
        try "- milk\n- bread\n".write(to: file, atomically: true, encoding: .utf8)

        let adopted = try #require(
            MarkdownStorageMigrator(rootURL: root).adopt(fileAt: file, knownSpaces: [])
        )
        #expect(adopted.title == "shopping list")
        #expect(adopted.body.contains("milk"))
    }

    /// Without writing the identifier back, the next scan would not recognise the file and
    /// would adopt it again — one dropped note becoming many.
    @Test("Adoption writes the identifier into the same file, so a rescan finds it once")
    func adoptionIsIdempotent() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("notes.md")
        try "text".write(to: file, atomically: true, encoding: .utf8)

        let migrator = MarkdownStorageMigrator(rootURL: root)
        let adopted = try #require(migrator.adopt(fileAt: file, knownSpaces: []))

        #expect(FileManager.default.fileExists(atPath: file.path))
        let rescan = migrator.importAll(knownSpaces: [])
        #expect(rescan.unidentifiedFiles.isEmpty)
        #expect(rescan.documents.map(\.id) == [adopted.id])
    }

    @Test("A file dropped into a space folder is filed into that space")
    func adoptsIntoSpace() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let directory = root.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("plan.md")
        try "text".write(to: file, atomically: true, encoding: .utf8)

        let adopted = try #require(
            MarkdownStorageMigrator(rootURL: root).adopt(fileAt: file, knownSpaces: [work])
        )
        #expect(adopted.spaceID == work.id)
    }

    @Test("A file that cannot be read is not adopted")
    func refusesUnreadableFile() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let missing = root.appendingPathComponent("nothing-here.md")
        #expect(MarkdownStorageMigrator(rootURL: root).adopt(fileAt: missing, knownSpaces: []) == nil)
    }

    // MARK: - Import

    @Test("Exported documents import back identically")
    func roundTrip() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let original = document("Notes", space: work.id, body: "# Heading\n\ntext\n")
        let migrator = MarkdownStorageMigrator(rootURL: root)

        #expect(migrator.export(documents: [original], spaces: [work]).isSuccess)
        let imported = migrator.importAll(knownSpaces: [work])

        #expect(imported.documents.count == 1)
        let restored = try #require(imported.documents.first)
        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.body == original.body)
        #expect(restored.spaceID == work.id)
    }

    @Test("Import finds documents in nested folders")
    func importsNested() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let deep = root.appendingPathComponent("Work/Projects")
        try? FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let file = deep.appendingPathComponent("nested.md")
        let contents = MarkdownDocumentFile.render(document("Nested"))
        try? contents.write(to: file, atomically: true, encoding: .utf8)

        let imported = MarkdownStorageMigrator(rootURL: root).importAll(knownSpaces: [])
        #expect(imported.documents.count == 1)
    }

    @Test("A _space.md is never imported as a document")
    func skipsSpaceFiles() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent(SpaceFile.filename)
        try? SpaceFile.render(Space(name: "Work")).write(to: file, atomically: true, encoding: .utf8)

        let imported = MarkdownStorageMigrator(rootURL: root).importAll(knownSpaces: [])
        #expect(imported.documents.isEmpty)
    }

    @Test("Hidden folders are skipped, so a .git directory is never walked")
    func skipsHiddenFolders() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let git = root.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let file = git.appendingPathComponent("stray.md")
        try? MarkdownDocumentFile.render(document("Stray"))
            .write(to: file, atomically: true, encoding: .utf8)

        let imported = MarkdownStorageMigrator(rootURL: root).importAll(knownSpaces: [])
        #expect(imported.documents.isEmpty)
    }

    @Test("A file with no identifier is reported for import, not silently dropped")
    func reportsUnidentifiedFiles() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("handwritten.md")
        try? "just prose".write(to: file, atomically: true, encoding: .utf8)

        let imported = MarkdownStorageMigrator(rootURL: root).importAll(knownSpaces: [])
        #expect(imported.documents.isEmpty)
        #expect(imported.unidentifiedFiles.count == 1)
    }

    @Test("Importing from an empty folder yields nothing and no error")
    func importsEmptyFolder() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let imported = MarkdownStorageMigrator(rootURL: root).importAll(knownSpaces: [])
        #expect(imported.documents.isEmpty)
        #expect(imported.unidentifiedFiles.isEmpty)
    }

    // MARK: - Root preparation

    @Test("A missing root is created")
    func createsRoot() throws {
        let parent = temporaryRoot()
        defer { cleanUp(parent) }
        let root = parent.appendingPathComponent("Logue")

        try MarkdownStorageMigrator(rootURL: root).prepareRoot()
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test("An empty existing root is accepted")
    func acceptsEmptyRoot() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try MarkdownStorageMigrator(rootURL: root).prepareRoot()
    }

    /// Refusing protects someone else's folder from being merged into.
    @Test("A root holding unrelated files is refused")
    func refusesForeignRoot() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let stray = root.appendingPathComponent("tax-return.pdf")
        try? Data("x".utf8).write(to: stray)

        #expect(throws: (any Error).self) {
            try MarkdownStorageMigrator(rootURL: root).prepareRoot()
        }
    }

    @Test("A root holding only our own markdown is accepted, so re-enabling works")
    func acceptsOurOwnRoot() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let file = root.appendingPathComponent("Alpha.md")
        try MarkdownDocumentFile.render(document("Alpha"))
            .write(to: file, atomically: true, encoding: .utf8)

        try MarkdownStorageMigrator(rootURL: root).prepareRoot()
    }
}
