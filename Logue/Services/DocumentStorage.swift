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

    /// Documents that belong in the folder but have no file there, because writing one failed.
    ///
    /// Falling back to encrypted storage — which `save` does by returning `false` — is only half an
    /// answer on its own. In markdown mode the folder is the library: `loadDocuments` reads it and
    /// takes nothing else from encrypted storage but the trash, and a scan reads "no file" as a
    /// deletion. So a document whose write failed was written somewhere nothing reads, then trashed
    /// by the next scan for being missing from the folder. This set is what tells both of those
    /// apart from a real deletion.
    ///
    /// Persisted, because the failure outlives the launch that hit it — a full disk or a folder on
    /// an unmounted drive is still there tomorrow. An identifier leaves the set the moment a write
    /// for it succeeds, or the document is trashed.
    ///
    /// Extension-visible: +Rescan
    @ObservationIgnored private(set) var unwritableDocuments: Set<UUID> {
        didSet {
            guard unwritableDocuments != oldValue else { return }
            UserDefaults.standard.set(
                unwritableDocuments.map(\.uuidString),
                forKey: AppConstants.UserDefaultsKeys.unwritableDocuments
            )
        }
    }

    /// Extension-visible: +Rescan
    @ObservationIgnored var watcher: MarkdownFolderWatcher?

    /// A scan asked for while one was already running.
    ///
    /// Extension-visible: +Rescan
    @ObservationIgnored var hasPendingScan = false

    /// Which file each document occupies, remembered between saves.
    ///
    /// Building it means reading every `.md` file in the library to pull out its identifier. Doing
    /// that per save — which is per debounced keystroke batch — made typing cost O(library size) on
    /// the main actor. Dropped whenever the folder might have changed underneath it: a scan, a
    /// deletion, a mode switch.
    ///
    /// Extension-visible: +Rescan
    @ObservationIgnored var cachedFileIndex: [UUID: URL]?

    /// Which folder each space occupies, remembered between saves.
    ///
    /// The same walk as `cachedFileIndex` and the same reason, a level up: `export` needs it to
    /// place a file, so an uncached one read every `_space.md` in the library on every save. That
    /// is what made a bulk import quadratic in wall-clock — 500 notes each walking a 250-file tree.
    ///
    /// Cached and invalidated together with the file index, because both are derived from one walk
    /// and anything that stales one stales the other.
    @ObservationIgnored private var cachedSpaceFolders: SpaceFolderMap?

    /// Extension-visible: +Rescan, SpaceStore+MarkdownFolder
    func invalidateFileIndex() {
        cachedFileIndex = nil
        cachedSpaceFolders = nil
    }

    /// Fills whichever of the two caches is cold, from a **single** traversal.
    ///
    /// They were built independently, each calling its own `snapshot()`, so a cold cache cost two
    /// full walks — and every walk opens every `.md` in the library. The doc comments on both
    /// already claimed one walk; this is what makes that true. It matters most during a vault
    /// import, where creating each folder invalidates both and the next save re-reads a tree that
    /// is still growing.
    private func folderCaches(
        using migrator: MarkdownStorageMigrator, in spaces: [Space]
    ) -> (files: [UUID: URL], folders: SpaceFolderMap) {
        if let cachedFileIndex, let cachedSpaceFolders {
            return (cachedFileIndex, cachedSpaceFolders)
        }

        let snapshot = migrator.snapshot()
        let files = cachedFileIndex ?? migrator.fileIndex(using: snapshot)
        let folders = cachedSpaceFolders ?? migrator.spaceFolderMap(in: spaces, using: snapshot)
        cachedFileIndex = files
        cachedSpaceFolders = folders
        return (files, folders)
    }

    private func fileIndex(using migrator: MarkdownStorageMigrator) -> [UUID: URL] {
        if let cachedFileIndex {
            return cachedFileIndex
        }
        let index = migrator.fileIndex()
        cachedFileIndex = index
        return index
    }

    /// What the last scan of the folder found, for the rescan button's tooltip.
    private(set) var lastScanSummary: String?

    /// True while a scan the *user* asked for is running, so the button can spin.
    ///
    /// Separate from `isScanInFlight` on purpose: a scan triggered by coming back to the app should
    /// not flash the button every time the window is focused, but it still must not run alongside
    /// another one.
    private(set) var isScanning = false

    /// True while any scan is running, announced or not. The reentrancy guard.
    ///
    /// Extension-visible: +Rescan
    @ObservationIgnored var isScanInFlight = false

    /// Extension-visible: +Rescan
    func beginScan() {
        isScanning = true
    }

    /// Extension-visible: +Rescan
    func endScan(summary: String?) {
        isScanning = false
        recordScanSummary(summary)
    }

    /// Records what a scan found without claiming one is running.
    ///
    /// Extension-visible: +Rescan
    func recordScanSummary(_ summary: String?) {
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

        let stored = UserDefaults.standard.stringArray(forKey: AppConstants.UserDefaultsKeys.unwritableDocuments)
        unwritableDocuments = Set((stored ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// Forgets every recorded failure.
    ///
    /// Called wherever the folder stops being the library — turning markdown storage off, erasing
    /// or clearing the folder. In encrypted mode `save` returns before it could ever clear one, so
    /// without this an id recorded in markdown mode survives the switch and stays exempt from the
    /// deletion check for good.
    ///
    /// Extension-visible: +Rescan
    func clearUnwritableDocuments() {
        unwritableDocuments = []
    }

    /// Forgets recorded failures for documents that now have a file, or no longer exist.
    ///
    /// Extension-visible: +Rescan
    func clearUnwritable(_ ids: some Sequence<UUID>) {
        unwritableDocuments.subtract(ids)
    }

    /// Records that a document has no file in the folder, or that it has one again.
    ///
    /// Both directions matter. Forgetting to clear leaves a document permanently exempt from the
    /// deletion check, so removing its file in Finder would stop working — silently, which is the
    /// worst way for a folder-is-the-library promise to break.
    private func setUnwritable(_ isUnwritable: Bool, for id: UUID) {
        if isUnwritable {
            unwritableDocuments.insert(id)
        } else {
            unwritableDocuments.remove(id)
        }
    }

    // MARK: - Switching

    enum SwitchError: LocalizedError {
        case exportFailed(count: Int, firstReason: String)
        case folderUnavailable
        case folderIncomplete(found: Int, expected: Int)
        case reEncryptionIncomplete(count: Int)

        var errorDescription: String? {
            switch self {
            case let .exportFailed(count, reason):
                "\(count) document(s) could not be written, so nothing was changed. First problem: \(reason)"
            case .folderUnavailable:
                "The Logue folder could not be found, so nothing was changed. If it is on a drive "
                    + "that is not connected, or you moved it, put it back and try again."
            case let .reEncryptionIncomplete(count):
                "\(count) document(s) had not finished writing to encrypted storage, so the folder "
                    + "was left where it is. Your documents are safe in both places — try turning "
                    + "the setting off again."
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
        // `reconcile` just wrote a file for every document, so nothing is outstanding. Without
        // this an id recorded in an earlier markdown session stays exempt from the deletion check
        // even though its file is right there.
        clearUnwritableDocuments()
        invalidateFileIndex()
        startWatchingIfNeeded()
        logger.info("Switched document storage to plain markdown")
    }

    /// Moves the folder to the Trash, once its documents are durably encrypted elsewhere.
    ///
    /// Split out of `switchToEncrypted` and called only after the re-encryption has been awaited and
    /// checked. It used to run inside the switch, where "the documents are in hand" meant *in memory*
    /// — the caller then persisted them through an unawaited `Task` whose failures were log-only. A
    /// user who had worked for a month in markdown mode (documents created then have no encrypted
    /// copy at all) could turn the setting off, have the detached writes hit a full disk, be shown
    /// success, and find the only copy of that month in the Trash.
    func retireFolderAfterReEncryption(of documents: [WritingDocument]) throws {
        let missing = documents.filter { !$0.isTrashed && !hasEncryptedCopy(of: $0.id) }
        guard missing.isEmpty else {
            throw SwitchError.reEncryptionIncomplete(count: missing.count)
        }

        try MarkdownStorageMigrator(rootURL: Self.markdownRootURL).retireRoot()
        logger.info("Moved the documents folder to the Trash")
    }

    /// Whether a document has landed in encrypted storage.
    private func hasEncryptedCopy(of id: UUID) -> Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let url = support
            .appendingPathComponent("Logue/documents")
            .appendingPathComponent("\(id.uuidString).json")
        return FileManager.default.fileExists(atPath: url.path)
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

        // Documents the folder was never able to hold do not count against it. The retry on each
        // scan recovers the ones that can be written — a drive that came back — but a read-only
        // folder or a full disk never reconciles, and refusing on that count left the user unable
        // to turn markdown storage off at all, following advice (press Rescan) that cannot work.
        // Their content is in encrypted storage already, which is where this switch is taking it.
        let unreachable = unwritableDocuments.count
        let expected = max(0, expectedDocumentCount - unreachable)
        if unreachable > 0 {
            logger.info(
                "\(unreachable, privacy: .public) document(s) never reached the folder; not expecting them back"
            )
        }

        // A partially present folder is the dangerous case, because it looks like a successful
        // read of a smaller library. Refusing sends the user to Rescan, which reconciles the
        // difference visibly instead of destroying it.
        guard imported.documents.count >= expected else {
            throw SwitchError.folderIncomplete(
                found: imported.documents.count, expected: expected
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

        // The folder is no longer the library, so a record of which documents it failed to hold
        // means nothing — and `save` returns early in encrypted mode, so nothing else could ever
        // clear it. Left set, it would still be exempt from the deletion check on the way back.
        clearUnwritableDocuments()
        mode = .encrypted
        invalidateFileIndex()

        logger.info("Switched document storage back to encrypted")
        return documents
    }

    /// Empties the plain-markdown folder without changing the setting.
    ///
    /// For the "clear data" paths, which are not "turn this feature off": the folder went to the
    /// Trash and an empty one takes its place. Before this, clearing left the entire library sitting
    /// in plaintext in `~/Logue` while the app forgot it existed — the worst of both, since the data
    /// was still readable by anything on the Mac but no longer reachable from the app.
    func clearMarkdownFolderContents() throws {
        guard mode.isMarkdown else { return }

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        try migrator.retireRoot()
        try migrator.prepareRoot()
        // The folder these ids referred to is gone, so the record refers to nothing.
        clearUnwritableDocuments()
        invalidateFileIndex()
        logger.info("Emptied the documents folder")
    }

    /// Removes the plain-markdown folder and returns to encrypted storage, for "erase all data".
    ///
    /// The folder goes to the Trash rather than being deleted outright — the same rule as everywhere
    /// else, and here the user asked for erasure, so it is the one case where leaving nothing behind
    /// would also be defensible. The Trash still wins: "erase" is a button people press by mistake.
    func eraseMarkdownFolder() throws {
        stopWatching()
        try MarkdownStorageMigrator(rootURL: Self.markdownRootURL).retireRoot()
        // The folder is no longer the library, so a record of which documents it failed to hold
        // means nothing — and `save` returns early in encrypted mode, so nothing else could ever
        // clear it. Left set, it would still be exempt from the deletion check on the way back.
        clearUnwritableDocuments()
        mode = .encrypted
        invalidateFileIndex()
        logger.info("Erased the plain markdown folder and returned to encrypted storage")
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
            // Documents whose write failed come back too. They are the encrypted fallback `save`
            // takes when the folder cannot be written to, and without this the fallback wrote to
            // somewhere nothing ever read — the document was simply gone at the next launch.
            let fromFolderIDs = Set(fromFolder.map(\.id))
            let recovered = stored.filter {
                ($0.isTrashed || unwritableDocuments.contains($0.id)) && !fromFolderIDs.contains($0.id)
            }
            // Anything that reappeared in the folder is no longer missing a file.
            unwritableDocuments.subtract(fromFolderIDs)
            return fromFolder + recovered
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
            // A trashed document is *meant* to have no file, and it is read back from encrypted
            // storage on its own. Leaving it marked would exempt it from the deletion check
            // forever, including after it is restored.
            setUnwritable(false, for: document.id)
            return false
        }

        let migrator = liveMigrator
        // One traversal fills both. Asking for them separately meant a cold cache walked the tree
        // twice, and each walk reads the contents of every `.md` in the library.
        var (index, folders) = folderCaches(using: migrator, in: spaces)
        let result = migrator.export(
            documents: [document.content],
            spaces: spaces,
            reusing: index,
            folders: folders,
            // Only this document's space needs its identity rewritten. Rewriting every space's
            // `_space.md` on every save was N writes per keystroke batch for no gain.
            identitiesFor: spaces.filter { $0.id == document.spaceID }
        )
        // Kept current rather than dropped: the file this document now occupies is exactly what the
        // export just told us, so the next save does not have to read the folder again.
        if let written = result.writtenFiles[document.id] {
            index[document.id] = written
            cachedFileIndex = index
        } else {
            invalidateFileIndex()
        }
        saveDerived(document.derived)

        // Reporting a failed write as handled left the document in memory with no file *and* no
        // encrypted copy, because the caller takes this as "stored, nothing more to do". The next
        // scan then found it absent from the folder and trashed it. Saying so lets the caller fall
        // back to encrypted storage, which is the whole point of returning a Bool.
        guard result.isSuccess else {
            logger.error("Could not write a document to the markdown folder — falling back to encrypted storage")
            setUnwritable(true, for: document.id)
            return false
        }
        setUnwritable(false, for: document.id)
        return true
    }

    /// Removes a document's file, used when it is trashed or deleted.
    ///
    /// To the Trash, never `removeItem`. This is reached from `trashDocuments(inSpace:)`, which a
    /// scan can reach by deciding a space no longer exists — so a wrong decision anywhere upstream
    /// used to erase live files outright. It should cost the user a trip to the Trash, not their
    /// text.
    func removeFile(for id: UUID) {
        // Before the mode guard: a document being deleted has nothing left to write, so keeping it
        // recorded as unwritable would only make the set grow for the life of the install.
        clearUnwritable([id])
        guard mode.isMarkdown else { return }

        let migrator = liveMigrator
        guard let url = fileIndex(using: migrator)[id] else { return }
        invalidateFileIndex()
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
            // Detached like the write below it: this runs on the main actor, from a save, and a
            // filesystem call there is a stall however small.
            Task.detached(priority: .utility) { [logger] in
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    logger.error(
                        "Could not remove empty derived state: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
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
