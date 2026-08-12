import Foundation
@testable import Logue
import Testing

/// The switch between storage modes, exercised at the folder level.
///
/// `DocumentStorage` owns the live root and the mode flag, and neither is injectable, so
/// these drive `TaskFolderStore` against a temporary directory — which is the half that
/// actually moves the user's data. What they establish is the property the switch depends
/// on: everything written on the way in is readable on the way out.
@Suite("TaskModeSwitch")
struct TaskModeSwitchTests {
    private final class TemporaryFolder {
        let url: URL

        init() {
            url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("logue-switch-\(UUID().uuidString)", isDirectory: true)
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

    private func sampleTasks() -> [TaskItem] {
        [
            TaskItem(title: "Send the deck", priority: .high, tags: ["launch"]),
            TaskItem(
                title: "Water the plants",
                recurrence: TaskRecurrence(unit: .week, interval: 1)
            ),
            TaskItem(title: "Archive Q2", status: .done, completedCount: 3),
            TaskItem(title: "送出簡報 📊", notes: "確認價格"),
        ]
    }

    @Test("Every task written on the way in is readable on the way out")
    func roundTripPreservesEveryTask() {
        withFolder { store in
            let original = sampleTasks()
            let result = store.exportAll(original)
            #expect(result.failed == 0)

            let readBack = store.loadAll()
            #expect(readBack.count == original.count)
            #expect(Set(readBack.map(\.id)) == Set(original.map(\.id)))
        }
    }

    @Test("A round trip preserves the fields the user would notice losing")
    func roundTripPreservesFields() throws {
        try withFolder { store in
            let original = sampleTasks()
            store.exportAll(original)

            let byID = Dictionary(
                store.loadAll().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            for task in original {
                let restored = try #require(byID[task.id])
                #expect(restored.title == task.title)
                #expect(restored.status == task.status)
                #expect(restored.priority == task.priority)
                #expect(restored.tags == task.tags)
                #expect(restored.recurrence == task.recurrence)
                #expect(restored.completedCount == task.completedCount)
                #expect(restored.notes == task.notes)
            }
        }
    }

    @Test("A completed task survives the switch as completed, not silently reopened")
    func completedTasksStayCompleted() throws {
        try withFolder { store in
            store.exportAll(sampleTasks())
            let done = try #require(store.loadAll().first { $0.title == "Archive Q2" })
            #expect(done.status == .done)
            #expect(done.completedCount == 3)
        }
    }

    @Test("Exporting twice does not duplicate the library")
    func exportIsIdempotent() {
        withFolder { store in
            let tasks = sampleTasks()
            store.exportAll(tasks)
            store.exportAll(tasks)
            #expect(store.loadAll().count == tasks.count)
        }
    }

    @Test("An export into a folder that already has the tasks leaves one file each")
    func reExportDoesNotStrandFiles() throws {
        try withFolder { store in
            let tasks = sampleTasks()
            store.exportAll(tasks)
            store.exportAll(tasks)

            let files = try FileManager.default
                .contentsOfDirectory(at: store.rootURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }
                .filter { !TaskFile.isFolderMarker(filename: $0.lastPathComponent) }
            #expect(files.count == tasks.count)
        }
    }

    @Test("A task edited in the folder is what comes back, not the version exported")
    func externalEditWins() throws {
        try withFolder { store in
            let task = TaskItem(title: "Send the deck")
            store.exportAll([task])

            var edited = task
            edited.title = "Send the revised deck"
            edited.priority = .high
            let url = try #require(store.url(forTaskID: task.id))
            try TaskFile.render(edited).write(to: url, atomically: true, encoding: .utf8)

            let readBack = try #require(store.loadAll().first)
            #expect(readBack.title == "Send the revised deck")
            #expect(readBack.priority == .high)
        }
    }

    @Test("An empty library round-trips to an empty library, not to a broken folder")
    func emptyLibraryRoundTrips() {
        withFolder { store in
            store.exportAll([])
            #expect(store.loadAll().isEmpty)
            #expect(store.exists)
        }
    }
}
