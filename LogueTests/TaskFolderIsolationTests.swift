import Foundation
@testable import Logue
import Testing

@Suite("TaskFolderIsolation")
struct TaskFolderIsolationTests {
    private let root = URL(fileURLWithPath: "/tmp/logue-test-root", isDirectory: true)

    /// Accumulates files the way a real walk would, so the computed properties under test
    /// are exercised rather than stubbed.
    private struct Builder {
        let root: URL
        var files: [URL] = []
        var contents: [URL: String] = [:]
        var componentsByFile: [URL: [String]] = [:]
        var directories: [[String]] = []

        mutating func addFile(at components: [String], body: String) {
            let url = components.reduce(root) { $0.appendingPathComponent($1) }
            files.append(url)
            contents[url] = body
            componentsByFile[url] = Array(components.dropLast())
        }

        mutating func addDirectory(_ components: [String]) {
            directories.append(components)
        }

        func snapshot() -> FolderSnapshot {
            FolderSnapshot(
                files: files.sorted { $0.path < $1.path },
                directories: directories,
                contents: contents,
                componentsByFile: componentsByFile,
                isComplete: true
            )
        }
    }

    private func document(titled title: String) -> String {
        "---\n_logue_id: \(UUID().uuidString)\ntitle: \(title)\n---\n"
    }

    /// A library with one loose document, optionally a marker-bearing task folder, and
    /// optionally some ordinary documents in subfolders.
    private func snapshot(
        taskFolder: String?,
        extraDocuments: [[String]] = []
    ) -> FolderSnapshot {
        var builder = Builder(root: root)
        builder.addFile(at: ["Notes.md"], body: document(titled: "Notes"))

        if let taskFolder {
            builder.addDirectory([taskFolder])
            builder.addFile(
                at: [taskFolder, TaskFile.folderMarkerFilename],
                body: TaskFile.folderMarkerContents(id: UUID())
            )
            builder.addFile(
                at: [taskFolder, "ship-it.md"],
                body: TaskFile.render(TaskItem(title: "Ship it"))
            )
        }

        for components in extraDocuments {
            builder.addDirectory(Array(components.dropLast()))
            builder.addFile(at: components, body: document(titled: "X"))
        }
        return builder.snapshot()
    }

    // MARK: - Recognition

    @Test("A folder carrying the marker is recognised as a task folder")
    func markerRecognised() {
        #expect(snapshot(taskFolder: "Tasks").taskFolders == [["Tasks"]])
    }

    @Test("Exclusion follows the marker, not the folder name")
    func exclusionFollowsMarkerNotName() {
        let snapshot = snapshot(taskFolder: "My Stuff")
        #expect(snapshot.taskFolders == [["My Stuff"]])
        #expect(snapshot.spaceDirectories.contains(["My Stuff"]) == false)
    }

    @Test("A folder merely named Tasks, with no marker, stays an ordinary space")
    func unmarkedTasksFolderIsASpace() {
        let snapshot = snapshot(taskFolder: nil, extraDocuments: [["Tasks", "Note.md"]])
        #expect(snapshot.taskFolders.isEmpty)
        #expect(snapshot.spaceDirectories.contains(["Tasks"]))
        #expect(snapshot.documentFiles.map(\.lastPathComponent).contains("Note.md"))
    }

    // MARK: - Exclusion

    @Test("Task files are not documents")
    func taskFilesExcludedFromDocuments() {
        let names = snapshot(taskFolder: "Tasks").documentFiles.map(\.lastPathComponent)
        #expect(names.contains("Notes.md"))
        #expect(names.contains("ship-it.md") == false)
        #expect(names.contains(TaskFile.folderMarkerFilename) == false)
    }

    @Test("A task folder is not offered as a space")
    func taskFolderExcludedFromSpaces() {
        #expect(snapshot(taskFolder: "Tasks").spaceDirectories.contains(["Tasks"]) == false)
    }

    @Test("Ordinary documents are untouched by the exclusion")
    func ordinaryDocumentsSurvive() {
        let snapshot = snapshot(taskFolder: "Tasks", extraDocuments: [["Work", "Plan.md"]])
        #expect(snapshot.documentFiles.map(\.lastPathComponent).sorted() == ["Notes.md", "Plan.md"])
        #expect(snapshot.spaceDirectories.contains(["Work"]))
    }

    // MARK: - No-op when absent

    @Test("With no task folder present, nothing about a scan changes")
    func noTaskFolderIsANoOp() {
        let snapshot = snapshot(taskFolder: nil)
        #expect(snapshot.taskFolders.isEmpty)
        #expect(snapshot.spaceDirectories == snapshot.directories)
        #expect(snapshot.documentFiles.count == 1)
    }

    // MARK: - Edge cases

    @Test("A marker file with no identity does not make a folder a task folder")
    func markerWithoutIdentityIgnored() {
        var builder = Builder(root: root)
        builder.addDirectory(["Tasks"])
        builder.addFile(at: ["Tasks", TaskFile.folderMarkerFilename], body: "no frontmatter here")
        builder.addFile(at: ["Tasks", "Note.md"], body: document(titled: "Note"))

        let snapshot = builder.snapshot()
        #expect(snapshot.taskFolders.isEmpty)
        #expect(snapshot.spaceDirectories.contains(["Tasks"]))
    }

    @Test("A copied task folder is also excluded, because being conservative is the safe direction")
    func duplicateTaskFoldersBothExcluded() {
        var builder = Builder(root: root)
        for name in ["Tasks", "Tasks copy"] {
            builder.addDirectory([name])
            builder.addFile(
                at: [name, TaskFile.folderMarkerFilename],
                body: TaskFile.folderMarkerContents(id: UUID())
            )
            builder.addFile(at: [name, "ship-it.md"], body: TaskFile.render(TaskItem(title: "Ship")))
        }

        let snapshot = builder.snapshot()
        #expect(snapshot.taskFolders.count == 2)
        #expect(snapshot.spaceDirectories.isEmpty)
        #expect(snapshot.documentFiles.isEmpty)
    }

    @Test("A folder nested inside a task folder is excluded too")
    func nestedFolderExcluded() {
        var builder = Builder(root: root)
        builder.addDirectory(["Tasks"])
        builder.addDirectory(["Tasks", "Archive"])
        builder.addFile(
            at: ["Tasks", TaskFile.folderMarkerFilename],
            body: TaskFile.folderMarkerContents(id: UUID())
        )
        builder.addFile(
            at: ["Tasks", "Archive", "old.md"],
            body: TaskFile.render(TaskItem(title: "Old"))
        )

        let snapshot = builder.snapshot()
        #expect(snapshot.spaceDirectories.isEmpty)
        #expect(snapshot.documentFiles.isEmpty)
    }

    // MARK: - The adoption hazard

    /// The failure this whole mechanism exists to prevent.
    ///
    /// A task file carries `_logue_task_id`, not `_logue_id`, so an import that walks every
    /// file cannot parse it as a document and files it under `unidentifiedFiles` instead.
    /// A scan then *adopts* those — stamping document frontmatter onto them once they settle
    /// — so every task in the library would turn into a document about two seconds after it
    /// was written, and the user's task list would quietly become notes.
    @Test("A task file is never offered for adoption as a document")
    func taskFilesAreNotAdoptable() {
        let migrator = MarkdownStorageMigrator(rootURL: root)
        let imported = migrator.importAll(knownSpaces: [], using: snapshot(taskFolder: "Tasks"))

        #expect(imported.unidentifiedFiles.isEmpty)
        #expect(imported.documents.count == 1)
        #expect(imported.documents.first?.title == "Notes")
    }

    @Test("A loose file with no identifier is still adoptable, so the exclusion is not too broad")
    func ordinaryUnidentifiedFilesStillAdoptable() {
        var builder = Builder(root: root)
        builder.addFile(at: ["Dropped.md"], body: "# Just some markdown\n")

        let migrator = MarkdownStorageMigrator(rootURL: root)
        let imported = migrator.importAll(knownSpaces: [], using: builder.snapshot())

        #expect(imported.unidentifiedFiles.map(\.lastPathComponent) == ["Dropped.md"])
    }

    // MARK: - Collision with an existing space

    /// Found by running the app against a real library.
    ///
    /// A user can already have a folder called `Tasks` holding a hundred documents — it is an
    /// obvious name for a space. If the app wrote its marker into that folder, the folder
    /// would read as a task folder, drop out of `spaceDirectories` and `spaceFiles`, and the
    /// space would look **vanished** — which routes to `trashDocuments(inSpace:)`.
    ///
    /// So space identity wins. `_space.md` is older, it holds the user's documents, and
    /// misreading it destroys them; misreading a task folder as a space costs nothing.
    @Test("A folder that is already a space is never treated as a task folder")
    func existingSpaceWinsOverTaskMarker() {
        var builder = Builder(root: root)
        builder.addDirectory(["Tasks"])
        builder.addFile(
            at: ["Tasks", SpaceFile.filename],
            body: "---\n\(SpaceFile.identifierKey): \(UUID().uuidString)\n---\n"
        )
        builder.addFile(
            at: ["Tasks", TaskFile.folderMarkerFilename],
            body: TaskFile.folderMarkerContents(id: UUID())
        )
        builder.addFile(at: ["Tasks", "Note.md"], body: document(titled: "Note"))

        let snapshot = builder.snapshot()
        #expect(snapshot.taskFolders.isEmpty)
        #expect(snapshot.spaceDirectories.contains(["Tasks"]))
        #expect(snapshot.spaceFiles.count == 1)
        #expect(snapshot.documentFiles.map(\.lastPathComponent).contains("Note.md"))
    }

    /// A `_space.md` in the task folder *itself* makes it a space — see
    /// `existingSpaceWinsOverTaskMarker`. One nested below it is a different case: the task
    /// folder's identity is unambiguous, so nothing inside it should surface as a space.
    @Test("A space file nested below a task folder is not read as a space")
    func spaceFileBelowTaskFolderIgnored() {
        var builder = Builder(root: root)
        builder.addDirectory(["Tasks"])
        builder.addDirectory(["Tasks", "Archive"])
        builder.addFile(
            at: ["Tasks", TaskFile.folderMarkerFilename],
            body: TaskFile.folderMarkerContents(id: UUID())
        )
        builder.addFile(
            at: ["Tasks", "Archive", SpaceFile.filename],
            body: "---\n\(SpaceFile.identifierKey): \(UUID().uuidString)\n---\n"
        )

        let snapshot = builder.snapshot()
        #expect(snapshot.taskFolders == [["Tasks"]])
        #expect(snapshot.spaceFiles.isEmpty)
        #expect(snapshot.spaceDirectories.isEmpty)
    }
}
