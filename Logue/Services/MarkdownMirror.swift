import Foundation
import OSLog

/// Keeps a folder of plain `.md` files in step with the encrypted document store.
///
/// The encrypted store stays the source of truth. The mirror exists so git, other
/// editors, and AI agents can work with documents as ordinary files — so it is
/// off by default and does nothing until the user picks a folder.
///
/// Sync is one document at a time and decided by `MirrorSyncDecision`. When both
/// sides have moved the mirror refuses to guess: it records a `MirrorConflict` and
/// leaves both copies untouched until the user chooses.
@MainActor
@Observable
final class MarkdownMirror {
    static let shared = MarkdownMirror()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MarkdownMirror")

    /// Unresolved conflicts, keyed by document.
    private(set) var conflicts: [UUID: MirrorConflict] = [:]

    /// Whether mirroring is on. Off until a folder is chosen.
    var isEnabled: Bool {
        folderURL != nil
    }

    /// Where mirror files live. Persisted as a security-scoped bookmark so access
    /// survives relaunch for a folder outside the app's own container.
    private(set) var folderURL: URL? {
        didSet { persistFolderBookmark() }
    }

    /// Fingerprint of the content each document last agreed with its file on. This is
    /// the base for three-way comparison; without it every difference looks like a
    /// conflict.
    private var lastSynced: [UUID: String] = [:]

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: CInt = -1
    private var pendingScan: Task<Void, Never>?

    private init() {
        restoreFolderBookmark()
        loadSyncState()
    }

    // MARK: - Enabling

    /// Points the mirror at a folder and performs an initial sync.
    func enable(folder: URL) {
        folderURL = folder
        loadSyncState()
        startWatching()
        syncAll()
    }

    /// Stops mirroring. Files already written are left in place — they are the user's.
    func disable() {
        stopWatching()
        folderURL = nil
        conflicts.removeAll()
    }

    // MARK: - Syncing

    /// Syncs every document. Used on enable and after external changes.
    func syncAll() {
        guard isEnabled else { return }
        for document in DocumentStore.shared.documents where !document.isTrashed {
            sync(document)
        }
    }

    /// Syncs one document, recording a conflict rather than choosing a side.
    func sync(_ document: WritingDocument) {
        guard let folder = folderURL else { return }

        let render = MirrorFile.render(document)
        let url = fileURL(for: document, in: folder)
        let contents = readFile(at: url)

        switch MirrorSyncDecision.decide(
            documentRender: render,
            fileContents: contents,
            lastSyncedFingerprint: lastSynced[document.id]
        ) {
        case .inSync:
            // Record agreement so a later one-sided edit is attributable.
            recordSynced(document.id, fingerprint: MirrorSyncDecision.fingerprint(of: render))
            conflicts.removeValue(forKey: document.id)

        case .writeFile:
            write(render, to: url, documentID: document.id)
            conflicts.removeValue(forKey: document.id)

        case .applyFile:
            guard let contents, let updated = MirrorFile.applying(contents, to: document) else {
                // A file that will not apply (missing or foreign identifier) is not an
                // error worth interrupting the user for; the app's copy stands.
                logger.info("Ignored an unmatched mirror file")
                return
            }
            DocumentStore.shared.updateDocument(updated)
            recordSynced(document.id, fingerprint: MirrorSyncDecision.fingerprint(of: contents))
            conflicts.removeValue(forKey: document.id)

        case .conflict:
            guard let contents else { return }
            conflicts[document.id] = MirrorConflict(
                documentID: document.id,
                documentTitle: document.title,
                appVersion: render,
                fileVersion: contents,
                fileURL: url,
                detectedAt: Date()
            )
            logger.warning("Mirror conflict recorded for one document")
        }
    }

    // MARK: - Resolving

    /// Applies the user's choice and clears the conflict.
    func resolve(_ conflict: MirrorConflict, using resolution: MirrorConflict.Resolution) {
        switch resolution {
        case .keepApp:
            write(conflict.appVersion, to: conflict.fileURL, documentID: conflict.documentID)

        case .keepFile:
            guard let document = DocumentStore.shared.documents
                .first(where: { $0.id == conflict.documentID }),
                let updated = MirrorFile.applying(conflict.fileVersion, to: document)
            else {
                logger.error("Could not apply the file version; conflict left in place")
                return
            }
            DocumentStore.shared.updateDocument(updated)
            recordSynced(
                conflict.documentID,
                fingerprint: MirrorSyncDecision.fingerprint(of: conflict.fileVersion)
            )
        }

        conflicts.removeValue(forKey: conflict.documentID)
    }

    func conflict(for documentID: UUID) -> MirrorConflict? {
        conflicts[documentID]
    }

    // MARK: - File I/O

    private func fileURL(for document: WritingDocument, in folder: URL) -> URL {
        let taken = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        )
        // A file already written for this document keeps its name, so renaming a
        // document does not orphan its mirror.
        if let existing = existingFileName(for: document.id, in: folder) {
            return folder.appendingPathComponent(existing)
        }
        return folder.appendingPathComponent(
            MirrorFilename.filename(for: document, avoiding: taken)
        )
    }

    /// Finds the file already claiming this document, by reading identifiers.
    private func existingFileName(for id: UUID, in folder: URL) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return nil }

        for name in names where name.hasSuffix(".\(MirrorFilename.fileExtension)") {
            let url = folder.appendingPathComponent(name)
            guard let contents = readFile(at: url) else { continue }
            if MirrorFile.identifier(in: contents) == id {
                return name
            }
        }
        return nil
    }

    private func readFile(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("Could not read a mirror file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write(_ contents: String, to url: URL, documentID: UUID) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            recordSynced(documentID, fingerprint: MirrorSyncDecision.fingerprint(of: contents))
        } catch {
            logger.error("Could not write a mirror file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Watching

    /// Watches the folder for external edits, coalescing bursts so a save from
    /// another editor does not trigger a scan per write.
    private func startWatching() {
        stopWatching()
        guard let folder = folderURL else { return }

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            logger.error("Could not watch the mirror folder")
            return
        }
        watchedDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchedDescriptor, fd >= 0 {
                close(fd)
                self?.watchedDescriptor = -1
            }
        }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        pendingScan?.cancel()
        pendingScan = nil
        watcher?.cancel()
        watcher = nil
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            try? await Task.sleep(for: AppConstants.Delays.mirrorScanDebounce)
            guard !Task.isCancelled else { return }
            self?.syncAll()
        }
    }

    // MARK: - Sync state persistence

    private var syncStateURL: URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support?.appendingPathComponent("Logue/mirror-sync-state.json")
    }

    private func recordSynced(_ id: UUID, fingerprint: String) {
        lastSynced[id] = fingerprint
        persistSyncState()
    }

    private func loadSyncState() {
        guard let url = syncStateURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        do {
            let data = try Data(contentsOf: url)
            lastSynced = try JSONDecoder().decode([UUID: String].self, from: data)
        } catch {
            // A lost base state means the next differing pair reads as a conflict —
            // safe, if noisier than ideal.
            logger.error("Could not load mirror sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistSyncState() {
        guard let url = syncStateURL else { return }
        let snapshot = lastSynced
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "MarkdownMirror")
                    .error("Could not save mirror sync state: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Folder bookmark

    private func persistFolderBookmark() {
        guard let folderURL else {
            UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaultsKeys.mirrorFolderBookmark)
            return
        }
        do {
            let data = try folderURL.bookmarkData(includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.mirrorFolderBookmark)
        } catch {
            logger.error("Could not save the mirror folder reference: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restoreFolderBookmark() {
        guard let data = UserDefaults.standard.data(
            forKey: AppConstants.UserDefaultsKeys.mirrorFolderBookmark
        )
        else { return }

        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            guard !isStale else {
                logger.info("Mirror folder reference is stale; mirroring stays off until re-chosen")
                return
            }
            folderURL = url
            startWatching()
        } catch {
            logger.error("Could not restore the mirror folder: \(error.localizedDescription, privacy: .public)")
        }
    }
}
