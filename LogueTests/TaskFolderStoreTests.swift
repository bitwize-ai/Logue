import Foundation
@testable import Logue
import Testing

@Suite("TaskFolderStore")
struct TaskFolderStoreTests {
    /// A fresh directory per test, removed when the test ends.
    private final class TemporaryFolder {
        let url: URL

        init() {
            url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("logue-tasks-\(UUID().uuidString)", isDirectory: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func withFolder(_ body: (TaskFolderStore) throws -> Void) rethrows {
        let temporary = TemporaryFolder()
        try body(TaskFolderStore(rootURL: temporary.url))
        _ = temporary
    }

    // MARK: - Preparing

    @Test("Preparing creates the folder and its marker")
    func prepareCreatesMarker() throws {
        try withFolder { store in
            try store.prepare()
            let marker = store.rootURL.appendingPathComponent(TaskFile.folderMarkerFilename)
            #expect(FileManager.default.fileExists(atPath: marker.path))

            let contents = try String(contentsOf: marker, encoding: .utf8)
            #expect(TaskFile.markerIdentifier(in: contents) != nil)
        }
    }

    @Test("Preparing twice does not replace an existing marker")
    func prepareIsIdempotent() throws {
        try withFolder { store in
            try store.prepare()
            let marker = store.rootURL.appendingPathComponent(TaskFile.folderMarkerFilename)
            let first = try String(contentsOf: marker, encoding: .utf8)

            try store.prepare()
            #expect(try String(contentsOf: marker, encoding: .utf8) == first)
        }
    }

    // MARK: - Refusing an existing space folder

    /// Found by running the app against a real library that had `~/Logue/Tasks` as a space
    /// holding a hundred documents.
    @Test("Preparing refuses a folder that is already a space")
    func prepareRefusesSpaceFolder() throws {
        try withFolder { store in
            try FileManager.default.createDirectory(
                at: store.rootURL, withIntermediateDirectories: true
            )
            try "---\n\(SpaceFile.identifierKey): \(UUID().uuidString)\n---\n".write(
                to: store.rootURL.appendingPathComponent(SpaceFile.filename),
                atomically: true,
                encoding: .utf8
            )

            #expect(store.isExistingSpaceFolder)
            #expect(throws: TaskFolderStore.PrepareError.self) { try store.prepare() }

            // And nothing was written, so the space is untouched.
            let marker = store.rootURL.appendingPathComponent(TaskFile.folderMarkerFilename)
            #expect(FileManager.default.fileExists(atPath: marker.path) == false)
        }
    }

    @Test("Saving into a space folder fails rather than colonising it")
    func saveRefusesSpaceFolder() throws {
        try withFolder { store in
            try FileManager.default.createDirectory(
                at: store.rootURL, withIntermediateDirectories: true
            )
            try "---\n\(SpaceFile.identifierKey): \(UUID().uuidString)\n---\n".write(
                to: store.rootURL.appendingPathComponent(SpaceFile.filename),
                atomically: true,
                encoding: .utf8
            )

            #expect(store.save(TaskItem(title: "Should not land")) == false)
        }
    }

    @Test("An ordinary folder is not mistaken for a space")
    func ordinaryFolderIsNotASpace() throws {
        try withFolder { store in
            try store.prepare()
            #expect(store.isExistingSpaceFolder == false)
        }
    }

    @Test("A folder that does not exist reads as empty rather than failing")
    func missingFolderReadsEmpty() {
        withFolder { store in
            #expect(store.exists == false)
            #expect(store.loadAll().isEmpty)
        }
    }

    // MARK: - Round trip

    @Test("A saved task is read back")
    func savedTaskIsReadBack() {
        withFolder { store in
            let task = TaskItem(title: "Send the deck", priority: .high, tags: ["launch"])
            #expect(store.save(task))

            let loaded = store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.id == task.id)
            #expect(loaded.first?.title == "Send the deck")
            #expect(loaded.first?.priority == .high)
            #expect(loaded.first?.tags == ["launch"])
        }
    }

    @Test("The marker is not read back as a task")
    func markerIsNotATask() {
        withFolder { store in
            store.save(TaskItem(title: "Only one"))
            #expect(store.loadAll().count == 1)
        }
    }

    @Test("Several tasks round-trip independently")
    func severalTasks() {
        withFolder { store in
            for title in ["First", "Second", "Third"] {
                store.save(TaskItem(title: title))
            }
            #expect(Set(store.loadAll().map(\.title)) == ["First", "Second", "Third"])
        }
    }

    @Test("Saving the same task twice updates it in place rather than duplicating")
    func saveUpdatesInPlace() {
        withFolder { store in
            var task = TaskItem(title: "Send the deck")
            store.save(task)
            task.priority = .high
            store.save(task)

            let loaded = store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.priority == .high)
        }
    }

    @Test("Retitling a task leaves exactly one file, not two claiming one identifier")
    func retitleLeavesOneFile() {
        withFolder { store in
            var task = TaskItem(title: "Old title")
            store.save(task)
            task.title = "New title"
            store.save(task)

            let loaded = store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.title == "New title")
        }
    }

    @Test("Two tasks with the same title get different files")
    func sameTitleDoesNotCollide() {
        withFolder { store in
            store.save(TaskItem(title: "Standup"))
            store.save(TaskItem(title: "Standup"))
            #expect(store.loadAll().count == 2)
        }
    }

    @Test("A hostile title cannot escape the folder")
    func hostileTitleStaysInFolder() throws {
        try withFolder { store in
            store.save(TaskItem(title: "../../escaped"))

            let names = try FileManager.default
                .contentsOfDirectory(at: store.rootURL, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)
            #expect(names.contains { $0.hasSuffix(".md") && !TaskFile.isFolderMarker(filename: $0) })
            #expect(store.loadAll().count == 1)
        }
    }

    @Test("Emoji and CJK survive a real write and read")
    func multiByteSurvivesDisk() {
        withFolder { store in
            store.save(TaskItem(title: "送出簡報 📊", notes: "確認價格 💰"))
            let loaded = store.loadAll().first
            #expect(loaded?.title == "送出簡報 📊")
            #expect(loaded?.notes == "確認價格 💰")
        }
    }

    // MARK: - Lookup and removal

    @Test("A task's file is found by the identifier inside it, so a rename still resolves")
    func lookupSurvivesRename() throws {
        try withFolder { store in
            let task = TaskItem(title: "Send the deck")
            store.save(task)

            let original = try #require(store.url(forTaskID: task.id))
            let renamed = store.rootURL.appendingPathComponent("renamed-by-hand.md")
            try FileManager.default.moveItem(at: original, to: renamed)

            // Compared by resolved path: `/var` is a symlink to `/private/var` on macOS, so
            // two URLs for one file can differ as strings.
            let found = try #require(store.url(forTaskID: task.id))
            #expect(found.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
            #expect(store.loadAll().first?.title == "Send the deck")
        }
    }

    @Test("Removing a task removes its file")
    func removeDeletesFile() {
        withFolder { store in
            let task = TaskItem(title: "Send the deck")
            store.save(task)
            store.remove(taskID: task.id)
            #expect(store.loadAll().isEmpty)
        }
    }

    @Test("Removing an unknown task is a no-op rather than an error")
    func removeUnknownIsNoOp() {
        withFolder { store in
            store.save(TaskItem(title: "Kept"))
            store.remove(taskID: UUID())
            #expect(store.loadAll().count == 1)
        }
    }

    // MARK: - Duplicates

    @Test("Two files claiming one identifier yield one task, not two")
    func duplicateIdentifiersCollapse() throws {
        try withFolder { store in
            let task = TaskItem(title: "Send the deck")
            store.save(task)

            // A copy, as Finder's "Duplicate" would produce.
            let copy = store.rootURL.appendingPathComponent("copy.md")
            try TaskFile.render(task).write(to: copy, atomically: true, encoding: .utf8)

            #expect(store.loadAll().count == 1)
        }
    }

    @Test("A file that is not a task is ignored rather than failing the read")
    func nonTaskFileIgnored() throws {
        try withFolder { store in
            store.save(TaskItem(title: "Real"))
            try "# Just a note\n".write(
                to: store.rootURL.appendingPathComponent("stray.md"),
                atomically: true,
                encoding: .utf8
            )

            let loaded = store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.title == "Real")
        }
    }

    // MARK: - Bulk export

    @Test("Exporting writes every task and reports no failures")
    func exportAllWritesEverything() {
        withFolder { store in
            let tasks = (0 ..< 5).map { TaskItem(title: "Task \($0)") }
            let result = store.exportAll(tasks)
            #expect(result.written == 5)
            #expect(result.failed == 0)
            #expect(store.loadAll().count == 5)
        }
    }

    @Test("Exporting an empty list is a no-op that still prepares the folder")
    func exportAllEmpty() {
        withFolder { store in
            let result = store.exportAll([])
            #expect(result.written == 0)
            #expect(result.failed == 0)
            #expect(store.exists)
        }
    }
}
