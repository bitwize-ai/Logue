import Foundation
import Testing

@testable import Logue

/// The review findings on #57, as tests.
///
/// Each case fails against the code as it stood before the fix it covers, which is the only
/// property that makes a regression test worth having. They are the paths whose failure mode is
/// losing a user's tasks, trashing their library, or hiding a space forever — including two
/// defects the fixes themselves introduced and a later review round caught.
@Suite("Task storage resilience")
struct TaskStorageResilienceTests {
    /// A fresh directory per test, removed when the test ends.
    private final class TemporaryFolder {
        let url: URL

        init() {
            url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("logue-resilience-\(UUID().uuidString)", isDirectory: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Finding the folder after it is moved

    @Test("A tasks folder moved into a sub-folder is still found")
    func movedFolderIsStillFound() throws {
        // Same promise as renaming, one Finder gesture over: the lookup searched only the root's
        // immediate children, so dragging Tasks/ into another folder emptied the task list while
        // the marker kept those files out of the document library too — reachable from nowhere.
        let temporary = TemporaryFolder()
        let root = temporary.url
        let moved = root.appendingPathComponent("Work/Tasks", isDirectory: true)
        try TaskFolderStore(rootURL: moved).prepare()

        #expect(TaskFolderStore.markedFolder(in: root)?.standardizedFileURL == moved.standardizedFileURL)
        _ = temporary
    }

    @Test("A marked folder that a space has claimed is not the tasks folder")
    func spaceIdentityWinsOverTheMarker() throws {
        // The precedence the snapshot already applies: space identity is older, holds documents,
        // and misreading it destroys them.
        let temporary = TemporaryFolder()
        let root = temporary.url
        let contested = root.appendingPathComponent("Tasks", isDirectory: true)
        try TaskFolderStore(rootURL: contested).prepare()
        try write("---\n_logue_space_id: \(UUID().uuidString)\n---\n",
                  to: contested.appendingPathComponent(SpaceFile.filename))

        #expect(TaskFolderStore.markedFolder(in: root) == nil)
        _ = temporary
    }

    // MARK: - Telling a partial read from an empty one

    @Test("A task file that cannot be parsed is reported, not silently dropped")
    func brokenTaskFileIsCounted() throws {
        // Ten files of which three are corrupt still returned seven tasks, and testing for
        // emptiness called that a complete read — then the folder was trashed with those three
        // inside, and a task created during markdown mode has no other copy.
        let temporary = TemporaryFolder()
        let folder = TaskFolderStore(rootURL: temporary.url)
        try folder.prepare()

        var task = TaskItem(id: UUID())
        task.title = "Water the plants"
        #expect(folder.save(task))

        // Carries a task identifier that is not a UUID: presents as a task, cannot be parsed.
        try write("---\n_logue_task_id: not-a-uuid\ntitle: Broken\n---\n",
                  to: temporary.url.appendingPathComponent("broken.md"))

        let loaded = folder.load()
        #expect(loaded.tasks.count == 1)
        #expect(loaded.unreadableTaskFiles == 1)
        #expect(loaded.isComplete == false)
        _ = temporary
    }

    @Test("A plain note dropped in the folder is ignored rather than blocking the switch")
    func nonTaskFileIsNotCounted() throws {
        // The converse failure: counting every .md made one stray note look like a missing task
        // and refused to retire a folder that was in fact complete.
        let temporary = TemporaryFolder()
        let folder = TaskFolderStore(rootURL: temporary.url)
        try folder.prepare()
        try write("# Shopping\n\nnothing to do with tasks\n",
                  to: temporary.url.appendingPathComponent("note.md"))

        let loaded = folder.load()
        #expect(loaded.tasks.isEmpty)
        #expect(loaded.unreadableTaskFiles == 0)
        #expect(loaded.isComplete)
        _ = temporary
    }

    // MARK: - A child of a stepped-aside folder

    @Test("A sub-space resolves under its parent's real folder, not its parent's name")
    func childFollowsTheParentsClaimedFolder() {
        // A space stepped past the tasks folder is named "Tasks" while occupying "Tasks 2".
        // Deriving the child's whole path from ancestor names put it at "Tasks/Q3" — inside the
        // live tasks folder, where the snapshot excludes it from every later scan. The space and
        // its documents do not come back from a rescan; they stop existing to the app.
        let parent = Space(name: "Tasks")
        let child = Space(name: "Q3", parentID: parent.id)
        let folders = SpaceFolderMap(componentsByID: [parent.id: ["Tasks 2"]])

        #expect(folders.components(forSpace: child.id, in: [parent, child]) == ["Tasks 2", "Q3"])
    }

    @Test("A space with no folder anywhere in its chain still resolves by name")
    func unclaimedChainFallsBackToNames() {
        let parent = Space(name: "Work")
        let child = Space(name: "Q3", parentID: parent.id)

        #expect(SpaceFolderMap().components(forSpace: child.id, in: [parent, child]) == ["Work", "Q3"])
    }

    @Test("A cycle in the parent chain terminates")
    func cyclicParentChainTerminates() {
        // Not reachable through the UI, but the walk must not hang on corrupted data — the same
        // guarantee SpaceFolderLayout makes.
        let first = Space(name: "A")
        let second = Space(name: "B", parentID: first.id)
        var cyclic = first
        cyclic.parentID = second.id

        let components = SpaceFolderMap().components(forSpace: second.id, in: [cyclic, second])
        #expect(components.isEmpty == false)
    }

    // MARK: - Renaming a space must not move the tasks folder

    /// A space named "Tasks" is given the folder "Tasks 2", so its name and its folder
    /// disagree until the next scan reconciles them. Inside that window, renaming the space
    /// derived the *old name* — "Tasks" — as the source, which is the live tasks folder: the
    /// rename moved every task file out of it and stamped `_space.md` on top of them. Tasks
    /// written in markdown mode have no encrypted copy, so that folder held the only one.
    @Test("Renaming a space never moves the tasks folder")
    func renameDoesNotStealTheTasksFolder() throws {
        let temporary = TemporaryFolder()
        let root = temporary.url
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let tasks = root.appendingPathComponent(TaskFile.folderName, isDirectory: true)
        try TaskFolderStore(rootURL: tasks).prepare()
        var task = TaskItem(id: UUID())
        task.title = "Water the plants"
        #expect(TaskFolderStore(rootURL: tasks).save(task))

        // The space still carries the name it was created with, while its folder is "Tasks 2".
        var space = Space(name: "Tasks")
        let migrator = MarkdownStorageMigrator(
            rootURL: root,
            retireFile: { try FileManager.default.removeItem(at: $0) }
        )
        try migrator.createFolder(for: space, in: [space])

        space.name = "Projects"
        try migrator.moveFolder(from: ["Tasks"], for: space, in: [space])

        // The tasks folder is untouched: still marked, still holding the task.
        #expect(TaskFolderStore(rootURL: tasks).isMarkedTaskFolder)
        #expect(TaskFolderStore(rootURL: tasks).loadAll().count == 1)
        #expect(FileManager.default.fileExists(
            atPath: tasks.appendingPathComponent(SpaceFile.filename).path
        ) == false)
        _ = temporary
    }

    @Test("A stray marker at the library root does not make the root the tasks folder")
    func rootIsNeverTheTasksFolder() throws {
        // `clearAllData` trashes `folderStore.rootURL`. Resolving that to the library root put
        // every space and document in the Trash from a dialog offering to remove sample data.
        let temporary = TemporaryFolder()
        let root = temporary.url
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(TaskFile.folderMarkerContents(id: UUID()),
                  to: root.appendingPathComponent(TaskFile.folderMarkerFilename))

        #expect(TaskFolderStore.markedFolder(in: root) == nil)
        _ = temporary
    }

    // MARK: - Bounding the folder search

    @Test("A marker buried below the space-depth cap is not searched for")
    func searchIsBoundedToTheSpaceDepthCap() throws {
        // The root is documented as somewhere to point at an existing vault, and this resolves
        // on every task read and write. A marker deeper than a space hierarchy can reach is not
        // somewhere the app can have put one, so the walk stops rather than paying for it.
        let temporary = TemporaryFolder()
        let root = temporary.url
        let deep = (0 ... SpaceFolderLayout.maxDepth + 2)
            .reduce(root) { $0.appendingPathComponent("d\($1)", isDirectory: true) }
        try TaskFolderStore(rootURL: deep).prepare()

        #expect(TaskFolderStore.markedFolder(in: root) == nil)
        _ = temporary
    }

    @Test("A tasks folder one level down is still found")
    func shallowNestingIsStillFound() throws {
        // The bound must not undo the moved-folder fix it sits beside.
        let temporary = TemporaryFolder()
        let root = temporary.url
        let moved = root.appendingPathComponent("Archive/Tasks", isDirectory: true)
        try TaskFolderStore(rootURL: moved).prepare()

        #expect(TaskFolderStore.markedFolder(in: root)?.standardizedFileURL == moved.standardizedFileURL)
        _ = temporary
    }
}
