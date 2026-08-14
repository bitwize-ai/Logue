import Foundation
import OSLog

/// Every filesystem operation on the tasks folder.
///
/// Takes its root as a parameter rather than reading a singleton, so it is testable against
/// a temporary directory — the same reason `MarkdownFolderScan` does. `TaskStorage` is the
/// thing that knows *which* root is live; this only knows how to read and write one.
struct TaskFolderStore {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "TaskFolderStore")

    /// The folder itself, e.g. `~/Logue/Tasks`.
    ///
    /// Symlinks resolved on the way in, so every URL this type produces is comparable with
    /// every URL `FileManager` hands back. Without it the two disagree — `appendingPathComponent`
    /// keeps `/var/...` while `contentsOfDirectory` returns `/private/var/...` — and `save`
    /// read "same file" as "different file", trashing the file it had just written.
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath()
    }

    // MARK: - Folder

    enum PrepareError: LocalizedError {
        case folderIsASpace(name: String)

        var errorDescription: String? {
            switch self {
            case let .folderIsASpace(name):
                "The folder \"\(name)\" is already one of your spaces, so tasks cannot be "
                    + "stored there. Rename that space or its folder and try again."
            }
        }
    }

    /// Whether this folder already carries a space identity.
    var isExistingSpaceFolder: Bool {
        let spaceFile = rootURL.appendingPathComponent(SpaceFile.filename)
        return FileManager.default.fileExists(atPath: spaceFile.path)
    }

    /// Creates the folder and its marker if they are not there.
    ///
    /// The marker is what makes the folder recognisable by identity rather than by name, so
    /// renaming it in Finder keeps tasks working and keeps them out of the document library.
    ///
    /// Refuses outright when the folder is already a space. `Tasks` is an obvious name for a
    /// space and users have one; colonising it would put two identities on one folder. The
    /// snapshot already resolves that in the space's favour, so this would only ever produce a
    /// tasks folder the app then declines to read — better to say so than to write nothing and
    /// look like it worked.
    func prepare() throws {
        guard !isExistingSpaceFolder else {
            throw PrepareError.folderIsASpace(name: rootURL.lastPathComponent)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let marker = rootURL.appendingPathComponent(TaskFile.folderMarkerFilename)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try TaskFile.folderMarkerContents(id: UUID())
            .write(to: marker, atomically: true, encoding: .utf8)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: rootURL.path)
    }

    /// Whether this folder carries the task marker.
    var isMarkedTaskFolder: Bool {
        markerIdentifier != nil
    }

    /// The identity written into this folder's marker, if it has one.
    var markerIdentifier: UUID? {
        let marker = rootURL.appendingPathComponent(TaskFile.folderMarkerFilename)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        do {
            return try TaskFile.markerIdentifier(in: String(contentsOf: marker, encoding: .utf8))
        } catch {
            Self.logger.error(
                "Could not read the task folder marker: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Locating the folder by identity

    /// The tasks folder under `root`, found by the marker it writes rather than by its name.
    ///
    /// The marker file tells the user that renaming the folder is safe — "it is how Logue
    /// recognises the folder, so that renaming the folder keeps working" — so the lookup has
    /// to honour that. Resolving by name instead means a folder renamed in Finder reads as
    /// missing, every task vanishes from the app, and the next save quietly recreates an empty
    /// one beside the real files, which that same marker keeps out of the document library.
    ///
    /// Ambiguity is not resolved by guessing: two marked folders keep the one actually named
    /// `TaskFile.folderName` if either is, and the situation is logged.
    static func markedFolder(in root: URL) -> URL? {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // A missing root is the ordinary case before the first export, not an error worth
            // shouting about; anything else is.
            if (error as NSError).code != NSFileReadNoSuchFileError {
                logger.error(
                    "Could not list the markdown root: \(error.localizedDescription, privacy: .public)"
                )
            }
            return nil
        }

        let marked = entries
            .filter { isDirectory($0) }
            .filter { TaskFolderStore(rootURL: $0).isMarkedTaskFolder }

        guard marked.count > 1 else { return marked.first }

        let byName = marked.first { $0.lastPathComponent == TaskFile.folderName }
        let chosen = byName ?? marked.min { $0.path < $1.path }
        let chosenName = chosen?.lastPathComponent ?? ""
        logger.error(
            "\(marked.count, privacy: .public) folders carry the task marker; using \(chosenName, privacy: .public)"
        )
        return chosen
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Reading

    /// Every task in the folder.
    ///
    /// Duplicates are resolved by identifier with the first sorted path winning, and logged —
    /// the same rule `duplicatedDocumentFiles` applies, and the same reason: two files
    /// claiming one record is not something to resolve silently.
    func loadAll() -> [TaskItem] {
        guard exists else { return [] }

        var byID: [UUID: TaskItem] = [:]
        var duplicates = 0

        for url in taskFileURLs() {
            guard let contents = read(at: url), let task = TaskFile.parse(contents) else { continue }
            if byID[task.id] != nil {
                duplicates += 1
                continue
            }
            byID[task.id] = task
        }

        if duplicates > 0 {
            Self.logger.info("\(duplicates, privacy: .public) duplicate task file(s) ignored")
        }
        return Array(byID.values)
    }

    /// The `.md` files that are not the marker, in a stable order.
    ///
    /// Sorted because two passes each pick "the first file with this identifier", and a
    /// duplicated file makes that a real choice — unsorted, two passes could disagree.
    private func taskFileURLs() -> [URL] {
        do {
            return try FileManager.default
                .contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }
                .filter { !TaskFile.isFolderMarker(filename: $0.lastPathComponent) }
                .sorted { $0.path < $1.path }
        } catch {
            Self.logger.error(
                "Could not list the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    /// How many task files the folder holds, or `nil` when it could not be listed.
    ///
    /// The distinction matters at exactly one moment: the folder is trashed after a switch out
    /// of markdown mode, so "read back nothing because it is empty" and "read back nothing
    /// because the listing failed" must not look the same.
    var taskFileCount: Int? {
        do {
            return try FileManager.default
                .contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }
                .count { !TaskFile.isFolderMarker(filename: $0.lastPathComponent) }
        } catch {
            Self.logger.error(
                "Could not count the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func read(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger.error(
                "Could not read a task file: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// The file currently holding this task.
    ///
    /// Found by the identifier inside it rather than by recomputing a name from the title,
    /// so a file the user renamed in Finder is still found.
    func url(forTaskID id: UUID) -> URL? {
        guard exists else { return nil }
        for url in taskFileURLs() {
            guard let contents = read(at: url), TaskFile.parse(contents)?.id == id else { continue }
            return url
        }
        return nil
    }

    // MARK: - Writing

    /// One pass over the folder: which file holds which task, and which names are taken.
    ///
    /// Built once and threaded through a batch. `save` used to walk the folder three times per
    /// task — `url(forTaskID:)` reads and parses every file, `currentFilenames` lists it again
    /// — and `exportAll` called `save` per task, so turning markdown storage on with 300 tasks
    /// was on the order of tens of thousands of reads, synchronously on the main actor.
    struct FolderIndex {
        var urlByTaskID: [UUID: URL]
        var filenames: Set<String>
    }

    /// Returns `nil` when the folder could not be listed — which must not be read as "empty",
    /// because an empty name set makes every new file look collision-free.
    func makeIndex() -> FolderIndex? {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: nil
            )
        } catch {
            Self.logger.error(
                "Could not list the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        var index = FolderIndex(urlByTaskID: [:], filenames: Set(urls.map(\.lastPathComponent)))
        let taskFiles = urls
            .filter { $0.pathExtension == "md" }
            .filter { !TaskFile.isFolderMarker(filename: $0.lastPathComponent) }
            // Sorted for the same reason `taskFileURLs` is: a duplicated identifier makes
            // "the first file with this id" a real choice, and two passes must agree on it.
            .sorted { $0.path < $1.path }

        for url in taskFiles {
            guard let contents = read(at: url), let task = TaskFile.parse(contents) else { continue }
            if index.urlByTaskID[task.id] == nil {
                index.urlByTaskID[task.id] = url
            }
        }
        return index
    }

    @discardableResult
    func save(_ task: TaskItem) -> Bool {
        do {
            try prepare()
        } catch {
            Self.logger.error(
                "Could not prepare the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        guard var index = makeIndex() else { return false }
        return write(task, index: &index)
    }

    /// Writes one task against an index, updating it so a batch stays consistent.
    ///
    /// Assumes `prepare()` has already run.
    func write(_ task: TaskItem, index: inout FolderIndex) -> Bool {
        do {
            let existing = index.urlByTaskID[task.id]
            var taken = index.filenames
            // Its own current name is not a collision with itself.
            if let existing {
                taken.remove(existing.lastPathComponent)
            }

            let filename = TaskFile.filename(for: task, avoiding: taken)
            let destination = rootURL.appendingPathComponent(filename)
            try TaskFile.render(task).write(to: destination, atomically: true, encoding: .utf8)

            // A retitled task gets a new filename. Left behind, the old file would be read
            // back as a second task carrying the same identifier on the next load.
            //
            // Compared standardized, not raw: this branch deletes a file, so a false
            // "different" here destroys the write that just succeeded.
            if let existing, existing.standardizedFileURL != destination.standardizedFileURL {
                try FileManager.default.trashItem(at: existing, resultingItemURL: nil)
                index.filenames.remove(existing.lastPathComponent)
            }

            index.urlByTaskID[task.id] = destination
            index.filenames.insert(filename)
            return true
        } catch {
            Self.logger.error(
                "Could not write a task file: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Deleting

    /// To the Trash, never `removeItem`.
    ///
    /// A wrong decision anywhere upstream should cost the user a trip to the Trash, not
    /// their text — the same rule documents follow.
    func remove(taskID: UUID) {
        guard let url = url(forTaskID: taskID) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Self.logger.error(
                "Could not remove a task file: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Bulk

    /// Writes every task, reporting how many could not be written.
    ///
    /// Returns the count rather than throwing on the first failure: the caller is deciding
    /// whether a mode switch is safe, and "one of forty failed" is a different answer from
    /// "the first one failed".
    func exportAll(_ tasks: [TaskItem]) -> (written: Int, failed: Int) {
        do {
            try prepare()
        } catch {
            Self.logger.error(
                "Could not prepare the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
            return (0, tasks.count)
        }

        // Walked once for the whole batch rather than once per task.
        guard var index = makeIndex() else { return (0, tasks.count) }

        var written = 0
        var failed = 0
        for task in tasks {
            if write(task, index: &index) {
                written += 1
            } else {
                failed += 1
            }
        }
        return (written, failed)
    }
}
