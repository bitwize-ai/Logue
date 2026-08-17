import Foundation
import OSLog

/// Where and how tasks are persisted.
///
/// Mirrors `DocumentStorage`, and follows **its** mode rather than carrying one of its own.
/// Two independent switches would let a user end up with plaintext tasks beside encrypted
/// documents — a privacy posture nobody chose deliberately, arrived at by forgetting a
/// second setting existed.
@MainActor
@Observable
final class TaskStorage {
    static let shared = TaskStorage()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "TaskStorage")

    private init() {}

    /// Tasks are stored as files exactly when documents are.
    private var isMarkdown: Bool {
        DocumentStorage.shared.mode.isMarkdown
    }

    // MARK: - Locations

    /// Where the folder is and which folder is ours — both, in one place that a test can build.
    ///
    /// Everything here used to be statics over `DocumentStorage.markdownRootURL` and
    /// `UserDefaults.standard`. See `TaskFolderLocator` for why it is not any more.
    nonisolated static let locator = TaskFolderLocator(root: { DocumentStorage.markdownRootURL })

    /// Forgets where the tasks folder is.
    nonisolated static func invalidateFolderLocation() {
        locator.invalidate()
    }

    nonisolated static var tasksFolderURL: URL {
        locator.folderURL
    }

    /// Stops believing in the remembered folder, for the moments the user says so.
    ///
    /// Call this *after* the folder is gone. Resolving it in order to trash it is itself an act
    /// that can re-learn it, so forgetting first is undone by the very next line.
    nonisolated static func forgetMarker() {
        locator.forget()
    }

    /// The folder store for the live location.
    var folderStore: TaskFolderStore {
        TaskFolderStore(rootURL: Self.tasksFolderURL)
    }

    private var encryptedDirectory: URL {
        // `.first ?? temporaryDirectory` rather than `[0]`: the array can be empty on
        // edge-case system configurations, and crashing on launch is the worst outcome.
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/tasks", isDirectory: true)
    }

    // MARK: - Reading

    func loadTasks() -> [TaskItem] {
        isMarkdown ? folderStore.loadAll() : loadEncrypted()
    }

    private func loadEncrypted() -> [TaskItem] {
        let directory = encryptedDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            return urls.filter { $0.pathExtension == "json" }.compactMap(readEncryptedTask)
        } catch {
            logger.error(
                "Could not list stored tasks: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func readEncryptedTask(at url: URL) -> TaskItem? {
        do {
            return try EncryptionManager.decryptCodable(TaskItem.self, from: Data(contentsOf: url))
        } catch {
            logger.error(
                "Could not read a stored task: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Writing

    /// Writes one task in the current mode. Returns whether the write succeeded.
    @discardableResult
    func save(_ task: TaskItem) -> Bool {
        isMarkdown ? folderStore.save(task) : writeEncrypted(task)
    }

    @discardableResult
    private func writeEncrypted(_ task: TaskItem) -> Bool {
        let directory = encryptedDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try EncryptionManager.encryptCodable(task)
            try data.write(
                to: directory.appendingPathComponent("\(task.id.uuidString).json"), options: .atomic
            )
            return true
        } catch {
            logger.error("Could not save a task: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Deleting

    func remove(taskID: UUID) {
        if isMarkdown {
            folderStore.remove(taskID: taskID)
        }
        // The encrypted copy goes in both modes: it is the fallback the folder falls back to,
        // and leaving it behind would resurrect the task on the next mode switch.
        removeEncrypted(taskID: taskID)
    }

    private func removeEncrypted(taskID: UUID) {
        let url = encryptedDirectory.appendingPathComponent("\(taskID.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error(
                "Could not remove a stored task: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Clearing

    /// Removes every stored task, in both modes.
    ///
    /// The encrypted copies are kept even while markdown mode is on — they are what makes the
    /// setting reversible — so a reset that only emptied `~/Logue` would leave them behind and
    /// the tasks would return on the next switch. Conversely a reset in encrypted mode never
    /// touched the folder at all.
    func clearAllData() {
        let directory = encryptedDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                logger.error(
                    "Could not clear stored tasks: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // To the Trash, never `removeItem` — this is the user's own text. `retire` owns the
        // resolve-trash-forget order, which is what kept being written the wrong way round here.
        do {
            try Self.locator.retire { folder in
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            }
        } catch {
            logger.error(
                "Could not clear the tasks folder: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Mode switching

    enum SwitchError: LocalizedError {
        case exportFailed(count: Int)

        var errorDescription: String? {
            switch self {
            case let .exportFailed(count):
                "\(count) task(s) could not be written to the folder."
            }
        }
    }

    /// Writes every task out to the folder, for the switch **into** markdown mode.
    ///
    /// Called before the mode flips, so a failure can abort the switch while the encrypted
    /// copies are still the live ones. The encrypted copies are kept on success too — they
    /// cost little and they are what makes turning this on reversible.
    func exportAll(_ tasks: [TaskItem]) throws {
        let result = folderStore.exportAll(tasks)
        guard result.failed == 0 else {
            throw SwitchError.exportFailed(count: result.failed)
        }
        logger.info("Wrote \(result.written, privacy: .public) task(s) to the folder")
    }

    /// What a re-encryption managed.
    ///
    /// `failed` is counted rather than logged because the folder is trashed after this: a
    /// write that did not land means the only copy of that task is inside the folder about to
    /// go, and the caller has to be able to refuse.
    struct ReEncryptResult {
        let tasks: [TaskItem]
        let failed: Int
        /// The folder is there but read back nothing — unreadable, not empty.
        let folderUnreadable: Bool

        var isComplete: Bool {
            failed == 0 && !folderUnreadable
        }
    }

    /// Reads the folder and re-encrypts what it finds, for the switch **out of** markdown mode.
    ///
    /// Reports the tasks now in encrypted storage, and whether every one of them got there.
    /// Anything created while markdown mode was on has no encrypted copy at all, so this is
    /// the only thing that carries it across — the same asymmetry
    /// `DocumentStorage.retireFolderAfterReEncryption` exists to handle.
    @discardableResult
    func reEncryptFromFolder() -> ReEncryptResult {
        let loaded = folderStore.load()
        let fromFolder = loaded.tasks
        var failed = 0
        for task in fromFolder where !writeEncrypted(task) {
            failed += 1
        }
        // Every task file that did not load, not just the case where none of them did. Ten
        // files of which three have hand-edited frontmatter still return seven tasks, and
        // testing for emptiness called that a complete read — then the folder was trashed with
        // those three inside, and a task created during markdown mode has no other copy.
        // A folder that exists but cannot be listed reads as zero files, so it counts too.
        let listingFailed = folderStore.exists && folderStore.taskFileCount == nil
        let unreadable = !loaded.isComplete || listingFailed

        // Merged with what encrypted storage already held: a task the folder never received
        // (an unwritable folder, a task trashed while in markdown mode) is still ours.
        var byID = Dictionary(loadEncrypted().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in fromFolder {
            byID[task.id] = task
        }
        logger.info("Re-encrypted \(fromFolder.count, privacy: .public) task(s) from the folder")
        if failed > 0 || unreadable {
            logger.error(
                "Re-encryption incomplete: \(failed, privacy: .public) failed, unreadable: \(unreadable, privacy: .public)"
            )
        }
        return ReEncryptResult(
            tasks: Array(byID.values), failed: failed, folderUnreadable: unreadable
        )
    }

    /// Whether a task has landed in encrypted storage, for the check before the folder is
    /// trashed. Mirrors `DocumentStorage.hasEncryptedCopy(of:)`.
    func hasEncryptedCopy(of id: UUID) -> Bool {
        FileManager.default.fileExists(
            atPath: encryptedDirectory.appendingPathComponent("\(id.uuidString).json").path
        )
    }
}
