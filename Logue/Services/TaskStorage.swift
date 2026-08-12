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

    /// `~/Logue/Tasks`.
    nonisolated static var tasksFolderURL: URL {
        DocumentStorage.markdownRootURL
            .appendingPathComponent(TaskFile.folderName, isDirectory: true)
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

    /// Reads the folder and re-encrypts what it finds, for the switch **out of** markdown mode.
    ///
    /// Returns the tasks now in encrypted storage. Anything created while markdown mode was on
    /// has no encrypted copy at all, so this is the only thing that carries it across — the
    /// same asymmetry `DocumentStorage.retireFolderAfterReEncryption` exists to handle.
    @discardableResult
    func reEncryptFromFolder() -> [TaskItem] {
        let fromFolder = folderStore.loadAll()
        for task in fromFolder {
            writeEncrypted(task)
        }

        // Merged with what encrypted storage already held: a task the folder never received
        // (an unwritable folder, a task trashed while in markdown mode) is still ours.
        var byID = Dictionary(loadEncrypted().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in fromFolder {
            byID[task.id] = task
        }
        logger.info("Re-encrypted \(fromFolder.count, privacy: .public) task(s) from the folder")
        return Array(byID.values)
    }
}
