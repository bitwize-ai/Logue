import Foundation
import OSLog

// MARK: - Mode

/// How documents are stored on disk.
enum DocumentStorageMode: String, Codable, Sendable {
    /// Encrypted JSON in Application Support. The default.
    case encrypted
    /// Plain `.md` files in `~/Logue`, editable outside the app.
    case markdown

    var isMarkdown: Bool {
        self == .markdown
    }
}

// MARK: - Storage

/// The single place that knows where and how documents are persisted.
///
/// `DocumentStore` delegates here so the rest of the app never learns which mode is
/// active. Derived AI state stays encrypted in Application Support in **both** modes —
/// it has no markdown representation, and keeping it out of the folder also keeps
/// `~/Logue` to files a person would want to see.
@MainActor
@Observable
final class DocumentStorage {
    static let shared = DocumentStorage()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentStorage")

    private(set) var mode: DocumentStorageMode {
        didSet {
            UserDefaults.standard.set(
                mode.rawValue, forKey: AppConstants.UserDefaultsKeys.documentStorageMode
            )
        }
    }

    /// Extension-visible: +Rescan
    @ObservationIgnored var watcher: MarkdownFolderWatcher?

    /// What the last scan of the folder found, for the rescan button's tooltip.
    private(set) var lastScanSummary: String?

    /// Set when turning the setting off could not move the folder to the Trash, so Settings can
    /// say so rather than leaving the user to notice a folder they were told would go.
    var folderRetirementFailed = false

    /// True while a scan is running, so the button can show it is doing something.
    private(set) var isScanning = false

    /// Extension-visible: +Rescan
    func beginScan() {
        isScanning = true
    }

    /// Extension-visible: +Rescan
    func endScan(summary: String?) {
        isScanning = false
        if let summary {
            lastScanSummary = summary
        }
    }

    /// A migrator wired to the echo filter, for every operation on the live folder.
    ///
    /// Extension-visible: +Rescan
    var liveMigrator: MarkdownStorageMigrator {
        MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
    }

    /// Where plain markdown documents live: `~/Logue`.
    ///
    /// In the home folder rather than Application Support because the promise is "edit these
    /// outside the app", and that has to mean somewhere a person can reach without being told a
    /// trick. Outside `~/Documents` because that is exactly what iCloud Drive's "Desktop &
    /// Documents Folders" option syncs — so keeping unencrypted notes there meant a setting the
    /// user turned on years ago could put them in the cloud today.
    nonisolated static var markdownRootURL: URL {
        homeURL.appendingPathComponent(AppConstants.appName)
    }

    /// Where the folder used to be, before it moved out of `~/Documents`.
    ///
    /// Kept so a folder left at the old path is moved rather than abandoned next to the new one —
    /// two folders that both look like the library is the confusion this design exists to remove.
    nonisolated static var legacyMarkdownRootURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return documents.appendingPathComponent(AppConstants.appName)
    }

    nonisolated private static var homeURL: URL {
        // `NSHomeDirectory()` rather than `FileManager.homeDirectoryForCurrentUser`: identical
        // while unsandboxed, and unambiguous about which one is meant if that ever changes.
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Moves a folder left behind at an old location, once.
    ///
    /// Only when the destination does not exist yet. Merging two folders that both claim to be the
    /// library would interleave two versions of the same documents, and there is no way to tell
    /// which of a pair is the one the user meant — so the second is left alone and logged instead.
    ///
    /// Static and taking both paths so the rule can be tested; it decides whether real user data
    /// moves.
    @discardableResult
    nonisolated static func moveFolderIfLeftBehind(from legacy: URL, to destination: URL) -> Bool {
        let manager = FileManager.default
        guard legacy.standardizedFileURL != destination.standardizedFileURL,
              manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: destination.path)
        else { return false }

        do {
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try manager.moveItem(at: legacy, to: destination)
            return true
        } catch {
            Logger(subsystem: AppConstants.bundleID, category: "DocumentStorage").error(
                "Could not move the documents folder to its new location: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Extension-visible: +Rescan
    func adoptLegacyFolderIfNeeded() {
        guard Self.moveFolderIfLeftBehind(
            from: Self.legacyMarkdownRootURL, to: Self.markdownRootURL
        )
        else { return }
        logger.info("Moved the documents folder out of Documents into the home folder")
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.documentStorageMode)
        mode = DocumentStorageMode(rawValue: raw ?? "") ?? .encrypted
    }

    // MARK: - Switching

    enum SwitchError: LocalizedError {
        case exportFailed(count: Int, firstReason: String)
        case folderUnavailable
        case folderIncomplete(found: Int, expected: Int)

        var errorDescription: String? {
            switch self {
            case let .exportFailed(count, reason):
                "\(count) document(s) could not be written, so nothing was changed. First problem: \(reason)"
            case .folderUnavailable:
                "The Logue folder could not be found, so nothing was changed. If it is on a drive "
                    + "that is not connected, or you moved it, put it back and try again."
            case let .folderIncomplete(found, expected):
                "The folder holds \(found) document(s) but Logue has \(expected), so nothing was "
                    + "changed. Press the rescan button in the sidebar to reconcile them first — "
                    + "switching now would discard the difference."
            }
        }
    }

    /// Switches to plain markdown, writing and verifying every document first.
    ///
    /// Ordered so failure is never destructive: write, verify, and only then flip the
    /// mode. The encrypted originals are **kept even on success** — they cost a few
    /// kilobytes and they are what makes turning this on reversible. They stop being read
    /// the moment the mode flips, and `DocumentStore.pruneStoredDocuments` clears the ones
    /// that have gone stale when markdown storage is turned off again.
    func switchToMarkdown(
        documents: [WritingDocument],
        spaces: [Space]
    ) throws {
        adoptLegacyFolderIfNeeded()

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        try migrator.prepareRoot()

        // `reconcile` rather than a plain export, because the folder may already be there from
        // a previous session. See its documentation for what goes wrong otherwise — briefly:
        // every document ends up with two files claiming the same identifier.
        let reconciled = migrator.reconcile(documents: documents.map(\.content), spaces: spaces)
        guard reconciled.isSuccess else {
            throw SwitchError.exportFailed(
                count: reconciled.export.failures.count,
                firstReason: reconciled.export.failures.values.first ?? "unknown"
            )
        }

        if !reconciled.retiredFiles.isEmpty {
            logger.info(
                "Moved \(reconciled.retiredFiles.count, privacy: .public) leftover file(s) to the Trash"
            )
        }

        // Derived state moves to the sidecar so it survives the switch.
        for document in documents where !document.derived.isEmpty {
            saveDerived(document.derived)
        }

        mode = .markdown
        startWatchingIfNeeded()
        logger.info("Switched document storage to plain markdown")
    }

    /// Switches back to encrypted storage, reading the folder first.
    ///
    /// `retiringFolder` moves `~/Logue` to the Trash once its documents are safely read back, and
    /// is the default the UI offers. A folder left behind is a second thing that looks like the
    /// library but is not: nothing writes to it, nothing reads from it, and edits made there
    /// quietly do nothing. The Trash, not deletion — those files are the user's, and "Put Back"
    /// has to remain possible.
    ///
    /// Keeping it is still offered, for someone who has the folder in git or is about to move it
    /// somewhere themselves.
    func switchToEncrypted(
        knownSpaces: [Space],
        retiringFolder: Bool,
        expectedDocumentCount: Int
    ) throws -> [WritingDocument] {
        // Refused rather than attempted when the folder is not there. Switching off reads the
        // folder and then prunes the encrypted copies of everything the folder did not account
        // for — so against a missing folder it read nothing and pruned the entire library. An
        // unmounted volume, a folder the user moved, and an unfinished sync all look like this.
        guard MarkdownFolderScan(rootURL: Self.markdownRootURL).isRootPresent else {
            throw SwitchError.folderUnavailable
        }

        // Stopped first: a scan arriving mid-switch would plan against a library that is
        // about to be replaced.
        stopWatching()

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        let imported = migrator.importAll(knownSpaces: knownSpaces)

        // A partially present folder is the dangerous case, because it looks like a successful
        // read of a smaller library. Refusing sends the user to Rescan, which reconciles the
        // difference visibly instead of destroying it.
        guard imported.documents.count >= expectedDocumentCount else {
            throw SwitchError.folderIncomplete(
                found: imported.documents.count, expected: expectedDocumentCount
            )
        }

        let documents = imported.documents.map { content in
            WritingDocument(content: content, derived: loadDerived(id: content.id))
        }

        if !imported.unidentifiedFiles.isEmpty {
            logger.info(
                "\(imported.unidentifiedFiles.count, privacy: .public) file(s) had no identifier and were left alone"
            )
        }

        mode = .encrypted

        // Last, and only once the documents are in hand: if reading the folder went wrong, the
        // folder is the only place that text exists.
        if retiringFolder {
            do {
                try migrator.retireRoot()
                logger.info("Moved the documents folder to the Trash")
            } catch {
                // The switch itself worked, so this does not fail it — the user is told, and can
                // move the folder themselves.
                logger.error("Could not move the documents folder to the Trash: \(error.localizedDescription, privacy: .public)")
                folderRetirementFailed = true
            }
        }

        logger.info("Switched document storage back to encrypted")
        return documents
    }

    // MARK: - Reading

    /// Loads all documents for the current mode, or `nil` when the encrypted store should
    /// handle it.
    ///
    /// Trashed documents come from encrypted storage even in markdown mode. They have no
    /// file — putting deleted notes in `~/Logue` would be its own surprise — so without
    /// this, emptying the trash would be the only way out of it and restoring would give
    /// back an empty document.
    func loadDocuments(knownSpaces: [Space], trashedFrom encryptedDirectory: URL) async -> [WritingDocument]? {
        guard mode.isMarkdown else { return nil }

        // Someone who enabled this before the folder moved has it at the old path; move it before
        // reading, or the app would find an empty folder and trash every document in the library.
        adoptLegacyFolderIfNeeded()

        let fromFolder = liveMigrator.importAll(knownSpaces: knownSpaces).documents.map { content in
            WritingDocument(content: content, derived: loadDerived(id: content.id))
        }

        do {
            let stored = try await DocumentStore.readEncryptedDocuments(in: encryptedDirectory)
            // Deduped by identifier, folder winning. A restored document keeps a stale encrypted
            // copy still marked trashed, and two entries for one id put the *trashed* one last —
            // where `rebuildIndexMap` lets it win every lookup, so the next save would take the
            // trashed branch and remove the user's file.
            let fromFolderIDs = Set(fromFolder.map(\.id))
            return fromFolder + stored.filter { $0.isTrashed && !fromFolderIDs.contains($0.id) }
        } catch {
            logger.error("Could not load trashed documents: \(error.localizedDescription, privacy: .public)")
            return fromFolder
        }
    }

    // MARK: - Writing

    /// Writes one document in the current mode. Returns whether it handled the write.
    ///
    /// A trashed document is **not** handled here: its file is removed and `false` is
    /// returned so it is written to encrypted storage instead. Trash therefore stays out of
    /// the folder while still being real, restorable, and encrypted.
    @discardableResult
    func save(_ document: WritingDocument, spaces: [Space]) -> Bool {
        guard mode.isMarkdown else { return false }

        if document.isTrashed {
            removeFile(for: document.id)
            return false
        }

        let migrator = liveMigrator
        let result = migrator.export(
            documents: [document.content], spaces: spaces, reusing: migrator.fileIndex()
        )
        if !result.isSuccess {
            logger.error("Could not write a document to the markdown folder")
        }
        saveDerived(document.derived)
        return true
    }

    /// Removes a document's file, used when it is trashed or deleted.
    ///
    /// To the Trash, never `removeItem`. This is reached from `trashDocuments(inSpace:)`, which a
    /// scan can reach by deciding a space no longer exists — so a wrong decision anywhere upstream
    /// used to erase live files outright. It should cost the user a trip to the Trash, not their
    /// text.
    func removeFile(for id: UUID) {
        guard mode.isMarkdown else { return }

        let migrator = liveMigrator
        guard let url = migrator.fileIndex()[id] else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            logger.error("Could not remove a document file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Derived sidecar

    private var derivedDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/derived")
    }

    func loadDerived(id: UUID) -> DocumentDerived? {
        let url = derivedDirectory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try EncryptionManager.decryptCodable(DocumentDerived.self, from: data)
        } catch {
            // Losing derived state costs cached analysis, not content, so this degrades
            // rather than failing the load.
            logger.error("Could not load derived state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveDerived(_ derived: DocumentDerived) {
        let directory = derivedDirectory
        let url = directory.appendingPathComponent("\(derived.id.uuidString).json")

        guard !derived.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        Task.detached(priority: .utility) { [logger] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try EncryptionManager.encryptCodable(derived)
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Could not save derived state: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
