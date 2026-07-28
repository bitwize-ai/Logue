import Foundation
@testable import Logue
import Testing

/// The other direction: what a change made *in the app* does to the folder.
///
/// This half did not exist, and its absence made the two sides fight. A space renamed in the app
/// left its folder under the old name, and since a scan cannot tell that from the user renaming
/// the folder, the next scan renamed the space back. A space deleted in the app left a folder
/// whose `_space.md` still named it, so the next scan created it again.
///
/// Everything here therefore has the same shape: make the change on disk, then prove a scan reads
/// the result as settled rather than as something to undo.
@Suite("Space folder writes")
struct SpaceFolderWriteTests {
    // MARK: - Harness

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logue-folders-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Retires by deleting, so a test run does not fill the user's Trash.
    private func migrator(_ root: URL) -> MarkdownStorageMigrator {
        MarkdownStorageMigrator(
            rootURL: root,
            retireFile: { try FileManager.default.removeItem(at: $0) }
        )
    }

    private func exists(_ root: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    // MARK: - Creating

    @Test("A space created in the app gets a folder with an identity")
    func createsFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        try migrator(root).createFolder(for: work, in: [work])

        #expect(exists(root, "Work"))
        #expect(exists(root, "Work/\(SpaceFile.filename)"))
    }

    /// A space with no folder is how a scan recognises a folder the user deleted. A space created
    /// in the app and left folderless would therefore delete itself on the next scan.
    @Test("A newly created space is not mistaken for one whose folder was deleted")
    func newSpaceIsNotSeenAsVanished() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.vanishedSpaceIDs(in: [work]).isEmpty)
    }

    @Test("A sub-space is created inside its parent's folder")
    func createsNestedFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let projects = Space(name: "Projects", parentID: work.id)
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work, projects])
        try migrator.createFolder(for: projects, in: [work, projects])

        #expect(exists(root, "Work/Projects/\(SpaceFile.filename)"))
    }

    // MARK: - Renaming

    @Test("Renaming a space moves its folder")
    func renameMovesFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        let previous = SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work])
        work.name = "Client Work"
        try migrator.moveFolder(from: previous, for: work, in: [work])

        #expect(exists(root, "Client Work"))
        #expect(exists(root, "Work") == false)
    }

    @Test("A renamed folder keeps the documents that were in it")
    func renameKeepsContents() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])
        try "note".write(
            to: root.appendingPathComponent("Work/plan.md"), atomically: true, encoding: .utf8
        )

        let previous = SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work])
        work.name = "Client Work"
        try migrator.moveFolder(from: previous, for: work, in: [work])

        #expect(exists(root, "Client Work/plan.md"))
    }

    /// Without the move, the folder still says "Work" while the space says "Client Work" — and the
    /// next scan believes the folder and renames the space back, undoing the user's edit.
    @Test("After a rename, a scan has nothing to undo")
    func renameSurvivesAScan() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        var work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        let previous = SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work])
        work.name = "Client Work"
        try migrator.moveFolder(from: previous, for: work, in: [work])

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.vanishedSpaceIDs(in: [work]).isEmpty)
        #expect(scan.spaceCreations(in: [work]).isEmpty)
    }

    // MARK: - Re-parenting

    @Test("Moving a space under another moves its folder inside")
    func moveUnderParent() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        var notes = Space(name: "Notes")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work, notes])
        try migrator.createFolder(for: notes, in: [work, notes])

        let previous = SpaceFolderLayout.directoryComponents(forSpace: notes.id, in: [work, notes])
        notes.parentID = work.id
        try migrator.moveFolder(from: previous, for: notes, in: [work, notes])

        #expect(exists(root, "Work/Notes"))
        #expect(exists(root, "Notes") == false)
    }

    @Test("After a move, a scan has nothing to undo")
    func moveSurvivesAScan() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        var notes = Space(name: "Notes")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work, notes])
        try migrator.createFolder(for: notes, in: [work, notes])

        let previous = SpaceFolderLayout.directoryComponents(forSpace: notes.id, in: [work, notes])
        notes.parentID = work.id
        try migrator.moveFolder(from: previous, for: notes, in: [work, notes])

        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.vanishedSpaceIDs(in: [work, notes]).isEmpty)
        #expect(scan.spaceCreations(in: [work, notes]).isEmpty)
    }

    // MARK: - Deleting

    @Test("Deleting a space retires its folder")
    func deleteRetiresFolder() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        try migrator.retireFolder(at: SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work]))

        #expect(exists(root, "Work") == false)
    }

    /// The folder holds an identity that names the space. Left behind, the next scan reads it as a
    /// folder the user made and creates the space all over again.
    @Test("A deleted space is not recreated by the next scan")
    func deletedSpaceStaysDeleted() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])
        try migrator.retireFolder(at: SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work]))

        // The space is gone from the store by this point, so the scan sees no spaces at all.
        let scan = MarkdownFolderScan(rootURL: root, adoptionSettleSeconds: 0)
        #expect(scan.spaceCreations(in: []).isEmpty)
    }

    @Test("Retiring a folder that is already gone is not an error")
    func retiringMissingFolderIsFine() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try migrator(root).retireFolder(at: ["Never Existed"])
    }

    /// Guards the path that would take the whole library with it.
    @Test("Retiring with no path does nothing")
    func retiringEmptyPathDoesNothing() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }
        try "x".write(to: root.appendingPathComponent("keep.md"), atomically: true, encoding: .utf8)

        try migrator(root).retireFolder(at: [])

        #expect(exists(root, "keep.md"))
    }

    // MARK: - Identity metadata

    @Test("A space's icon and colour reach its space file")
    func writesIconAndColour() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work", icon: "hammer", color: "blue")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        let contents = try String(
            contentsOf: root.appendingPathComponent("Work/\(SpaceFile.filename)"), encoding: .utf8
        )
        let identity = try #require(SpaceFile.identity(from: contents))
        #expect(identity.id == work.id)
        #expect(identity.icon == "hammer")
        #expect(identity.color == "blue")
    }

    @Test("Identities are written only into folders that exist")
    func doesNotCreateFoldersForIdentities() {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        // This is the write that runs on every save and every scan. If it created folders, a
        // folder the user deleted would come back within seconds.
        migrator(root).writeSpaceIdentities(spaces: [Space(name: "Work")])

        #expect(exists(root, "Work") == false)
    }

    // MARK: - The index the deletion rule depends on

    @Test("The folder index finds each space by its identifier, not its name")
    func indexesByIdentifier() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        let work = Space(name: "Work")
        let migrator = migrator(root)
        try migrator.createFolder(for: work, in: [work])

        // Renamed in Finder, so only the identifier still connects the two.
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("Work"), to: root.appendingPathComponent("Renamed")
        )

        #expect(migrator.spaceFolderMap().components(forSpace: work.id, in: []) == ["Renamed"])
    }

    @Test("A folder with no space file is not in the index")
    func ignoresFoldersWithoutIdentity() throws {
        let root = temporaryRoot()
        defer { cleanUp(root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Handmade"), withIntermediateDirectories: true
        )

        #expect(migrator(root).spaceFolderMap().claimedSpaceIDs.isEmpty)
    }
}
