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

    /// What the mirror is doing, for the toolbar indicator.
    enum SyncState: Equatable, Sendable {
        case off
        case idle
        case syncing(completed: Int, total: Int)

        var isSyncing: Bool {
            if case .syncing = self {
                return true
            }
            return false
        }
    }

    private(set) var state: SyncState = .off

    /// When the last full pass finished, for the indicator's tooltip.
    private(set) var lastSyncedAt: Date?

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

    /// Directory paths that could not be mapped to a space, remembered for this
    /// session.
    ///
    /// `SpaceStore.createSpace` de-duplicates sibling names, so a folder whose name
    /// clashes yields a space with a different name — which then will not match the
    /// folder. Without this guard the next scan would treat it as missing again and
    /// create another space, and so on indefinitely.
    private var unmappableDirectories: Set<String> = []

    private init() {
        restoreFolderBookmark()
        loadSyncState()
    }

    // MARK: - Enabling

    /// Points the mirror at a folder and performs an initial sync.
    func enable(folder: URL) {
        folderURL = folder
        unmappableDirectories.removeAll()
        state = .idle
        loadSyncState()
        startWatching()
        syncAll()
    }

    /// Stops mirroring. Files already written are left in place — they are the user's.
    func disable() {
        stopWatching()
        folderURL = nil
        conflicts.removeAll()
        unmappableDirectories.removeAll()
        state = .off
        lastSyncedAt = nil
    }

    // MARK: - Syncing

    /// Syncs every document, after taking in any structure created on disk.
    ///
    /// Directories are imported as spaces first, so a document found inside a
    /// hand-made folder can be filed into the space that folder now represents.
    func syncAll() {
        guard isEnabled, !state.isSyncing else { return }

        // One index of identifier → file per pass. Matching per document used to
        // enumerate and read every file, which is quadratic in the number of
        // documents; on a real library that is thousands of redundant reads.
        let index = buildFileIndex()

        importDirectoriesAsSpaces()
        adoptExternalFileMoves(using: index)

        let documents = DocumentStore.shared.documents.filter { !$0.isTrashed }
        state = .syncing(completed: 0, total: documents.count)

        for (offset, document) in documents.enumerated() {
            sync(document, index: index)
            state = .syncing(completed: offset + 1, total: documents.count)
        }

        lastSyncedAt = Date()
        state = .idle
    }

    /// Identifier → file location for every mirror file, built in one walk.
    private func buildFileIndex() -> [UUID: URL] {
        guard let folder = folderURL else { return [:] }

        var index: [UUID: URL] = [:]
        for url in markdownFiles(in: folder) {
            guard let contents = readFile(at: url),
                  let id = MirrorFile.identifier(in: contents)
            else { continue }
            // First file wins on a duplicated identifier — copying a mirror file
            // duplicates its id, and adopting both would ping-pong the document.
            if index[id] == nil {
                index[id] = url
            }
        }
        return index
    }

    // MARK: - Importing structure from disk

    /// Creates a space for every directory that does not have one yet.
    ///
    /// Shallowest first, so a parent exists before its children are considered.
    private func importDirectoriesAsSpaces() {
        guard let folder = folderURL else { return }

        for components in directoryPaths(in: folder).sorted(by: { $0.count < $1.count }) {
            let key = components.joined(separator: "/")
            guard !unmappableDirectories.contains(key) else { continue }

            let missing = MirrorLayout.missingComponents(
                forDirectoryComponents: components, in: SpaceStore.shared.spaces
            )
            guard !missing.isEmpty else { continue }

            // Everything above the missing tail already resolves.
            let existingDepth = components.count - missing.count
            var parentID = MirrorLayout.spaceID(
                forDirectoryComponents: Array(components.prefix(existingDepth)),
                in: SpaceStore.shared.spaces
            )

            for name in missing {
                guard let created = SpaceStore.shared.createSpace(name: name, parentID: parentID)
                else { break }
                parentID = created.id
                logger.info("Created a space for a folder found on disk")
            }

            // If the folder still does not resolve, the created space was renamed to
            // avoid a sibling clash. Stop trying rather than creating another space on
            // every scan.
            if MirrorLayout.spaceID(
                forDirectoryComponents: components, in: SpaceStore.shared.spaces
            ) == nil {
                unmappableDirectories.insert(key)
                logger.warning("A folder could not be mapped to a space; it will be ignored")
            }
        }
    }

    /// Refiles a document whose mirror file was moved into a different folder.
    ///
    /// The file's location is authoritative here: moving a file between folders is an
    /// unambiguous instruction, unlike an edit to its contents.
    private func adoptExternalFileMoves(using index: [UUID: URL]) {
        guard let folder = folderURL else { return }

        let byID = Dictionary(
            DocumentStore.shared.documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        for (id, url) in index {
            guard let document = byID[id] else { continue }

            let components = directoryComponents(of: url, under: folder)
            let spaceID = MirrorLayout.spaceID(
                forDirectoryComponents: components, in: SpaceStore.shared.spaces
            )
            guard spaceID != document.spaceID else { continue }

            var updated = document
            updated.spaceID = spaceID
            DocumentStore.shared.updateDocument(updated)
            logger.info("Refiled a document after its mirror file moved")
        }
    }

    /// Relative directory components of a file under the mirror root.
    private func directoryComponents(of file: URL, under folder: URL) -> [String] {
        let rootParts = folder.standardizedFileURL.pathComponents
        let fileParts = file.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileParts.count > rootParts.count else { return [] }
        return Array(fileParts.dropFirst(rootParts.count))
    }

    /// Every directory under the mirror root, as relative component lists.
    private func directoryPaths(in folder: URL) -> [[String]] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        else { return [] }

        var paths: [[String]] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { continue }

            let rootParts = folder.standardizedFileURL.pathComponents
            let parts = url.standardizedFileURL.pathComponents
            guard parts.count > rootParts.count else { continue }
            let components = Array(parts.dropFirst(rootParts.count))
            guard components.count <= MirrorLayout.maxDepth else { continue }
            paths.append(components)
        }
        return paths
    }

    /// Syncs one document, recording a conflict rather than choosing a side.
    ///
    /// `index` avoids re-walking the folder for every document during a full pass.
    func sync(_ document: WritingDocument, index: [UUID: URL]? = nil) {
        guard let folder = folderURL else { return }

        let render = MirrorFile.render(document)
        let url = fileURL(for: document, in: folder, index: index)
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

    /// Where a document's mirror file belongs, following its space hierarchy.
    ///
    /// A document already on disk keeps its filename but is **moved** when its space
    /// changes, so the folder tree tracks the sidebar instead of accumulating copies.
    private func fileURL(
        for document: WritingDocument,
        in folder: URL,
        index: [UUID: URL]? = nil
    ) -> URL {
        let directory = folder.appendingPathComponent(
            MirrorLayout.directoryComponents(
                forSpace: document.spaceID, in: SpaceStore.shared.spaces
            ).joined(separator: "/")
        )

        let existing = index?[document.id] ?? existingFile(for: document.id, in: folder)
        if let existing {
            let wanted = directory.appendingPathComponent(existing.lastPathComponent)
            if existing.standardizedFileURL != wanted.standardizedFileURL {
                move(existing, to: wanted)
            }
            return wanted
        }

        let taken = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        )
        return directory.appendingPathComponent(
            MirrorFilename.filename(for: document, avoiding: taken)
        )
    }

    /// Moves a mirror file when its document changes space, creating the destination
    /// directory. A failure leaves the original in place rather than losing it.
    private func move(_ source: URL, to destination: URL) {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            logger.error("Could not move a mirror file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Finds the file already claiming this document anywhere under the mirror root,
    /// by reading identifiers — so a file moved by hand is still recognised.
    private func existingFile(for id: UUID, in folder: URL) -> URL? {
        for url in markdownFiles(in: folder) {
            guard let contents = readFile(at: url) else { continue }
            if MirrorFile.identifier(in: contents) == id {
                return url
            }
        }
        return nil
    }

    /// Every `.md` file under the mirror root, skipping hidden directories so a `.git`
    /// folder is never walked.
    private func markdownFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == MirrorFilename.fileExtension }
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
