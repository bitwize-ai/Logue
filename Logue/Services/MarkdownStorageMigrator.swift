import Foundation
import OSLog

/// Moves documents between encrypted storage and a plain-markdown folder.
///
/// The root is injected rather than fixed, so migrations can be exercised against a
/// temporary directory. This code's only job is filesystem behaviour, and the failure it
/// exists to prevent — deleting encrypted originals after a bad write — is only real on
/// a real filesystem.
///
/// **Export verifies every file by reading it back.** The caller must treat anything
/// other than complete success as a reason to keep the originals.
struct MarkdownStorageMigrator {
    let rootURL: URL

    /// Told about every write, so the watcher can recognise our own events and not read a
    /// file back over the text the user is typing. `nil` for a one-off migration, where
    /// nothing is watching yet.
    let echoFilter: WriteEchoFilter?

    /// How a file that no longer belongs is disposed of.
    ///
    /// The Trash rather than deletion, so anything retired on the user's behalf is one
    /// "Put Back" away. Injectable only so a test run does not fill the real Trash.
    let retireFile: @Sendable (URL) throws -> Void

    init(
        rootURL: URL,
        echoFilter: WriteEchoFilter? = nil,
        retireFile: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.rootURL = rootURL
        self.echoFilter = echoFilter
        self.retireFile = retireFile
    }

    private var logger: Logger {
        Logger(subsystem: AppConstants.bundleID, category: "MarkdownStorageMigrator")
    }

    enum PrepareError: LocalizedError {
        case rootHoldsUnrelatedFiles(count: Int)
        case couldNotCreateRoot(String)

        var errorDescription: String? {
            switch self {
            case let .rootHoldsUnrelatedFiles(count):
                "That folder already contains \(count) unrelated item(s). "
                    + "Choose an empty folder so Logue does not mix its documents into it."
            case let .couldNotCreateRoot(reason):
                "The folder could not be created: \(reason)"
            }
        }
    }

    // MARK: - Results

    struct ExportResult {
        var writtenFiles: [UUID: URL] = [:]
        /// Document id → why it could not be written or verified.
        var failures: [UUID: String] = [:]

        var isSuccess: Bool {
            failures.isEmpty
        }
    }

    struct ImportResult {
        var documents: [DocumentContent] = []
        /// Markdown files carrying no identifier. Surfaced rather than dropped, so the
        /// caller can decide whether to adopt them as new documents.
        var unidentifiedFiles: [URL] = []
    }

    // MARK: - Root

    /// Creates the root, refusing a folder that already holds unrelated content.
    ///
    /// Merging into someone else's folder would scatter documents through their files and
    /// make "turn it off again" ambiguous. Our own markdown is accepted, so re-enabling
    /// after turning it off works.
    func prepareRoot() throws {
        let manager = FileManager.default

        if manager.fileExists(atPath: rootURL.path) {
            let entries = (try? manager.contentsOfDirectory(atPath: rootURL.path)) ?? []
            let unrelated = entries.filter { name in
                if name.hasPrefix(".") {
                    return false
                }
                if SpaceFile.isSpaceFile(filename: name) {
                    return false
                }
                if name.hasSuffix(".\(DocumentFilename.fileExtension)") {
                    return false
                }
                // A directory could be one of our space folders; allow it.
                var isDirectory: ObjCBool = false
                let path = rootURL.appendingPathComponent(name).path
                manager.fileExists(atPath: path, isDirectory: &isDirectory)
                return !isDirectory.boolValue
            }
            guard unrelated.isEmpty else {
                throw PrepareError.rootHoldsUnrelatedFiles(count: unrelated.count)
            }
            return
        }

        do {
            try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw PrepareError.couldNotCreateRoot(error.localizedDescription)
        }
    }

    // MARK: - Export

    /// Writes every document as markdown, verifying each by reading it back.
    ///
    /// Trashed documents are skipped: trash lives in the app, so a deleted document
    /// should not reappear as a file.
    ///
    /// `reusing` maps document ids to the files they already occupy. Pass it whenever the
    /// folder is the live store rather than a fresh export: a document must keep the file
    /// it already has, or renaming a title — or renaming the *file*, which the user is
    /// invited to do — would leave the old file behind next to the new one.
    func export(
        documents: [DocumentContent],
        spaces: [Space],
        reusing existing: [UUID: URL] = [:]
    ) -> ExportResult {
        var result = ExportResult()

        for content in documents where !content.isTrashed {
            let directory = rootURL.appendingPathComponent(
                SpaceFolderLayout.directoryComponents(forSpace: content.spaceID, in: spaces)
                    .joined(separator: "/")
            )
            let current = existing[content.id]
            let url = destination(for: content, in: directory, current: current)

            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let rendered = MarkdownDocumentFile.render(content)
                echoFilter?.expect(rendered, at: url)
                try rendered.write(to: url, atomically: true, encoding: .utf8)

                try verify(content, at: url)
                result.writtenFiles[content.id] = url

                // Only after the new file is verified, so a failed move never loses the
                // only copy.
                if let current, current.standardizedFileURL != url.standardizedFileURL {
                    try FileManager.default.removeItem(at: current)
                }
            } catch {
                result.failures[content.id] = error.localizedDescription
                logger.error("Export failed for one document: \(error.localizedDescription, privacy: .public)")
            }
        }

        // After the documents, not before: identities are only written into folders that already
        // exist, and the folder a document belongs in is created by the loop above. Writing them
        // first left a space whose only folder came from a document with no `_space.md` in it —
        // which the next scan read as a space with no folder, and deleted.
        writeSpaceFiles(spaces: spaces, into: &result)

        return result
    }

    // MARK: - Re-enabling into a folder that is already there

    struct ReconcileResult {
        var export = ExportResult()
        /// Files moved to the Trash because no live document claims them, or because their text
        /// had drifted from the document and was about to be overwritten.
        var retiredFiles: [URL] = []

        var isSuccess: Bool {
            export.isSuccess
        }
    }

    /// Brings a folder left over from a previous session into line with the library.
    ///
    /// Turning the setting on when a folder is already there is not the same as a first export,
    /// and treating it as one goes wrong in three ways — each of which silently undoes work:
    ///
    /// - A leftover file for a document that changed in the app makes the export pick a
    ///   *different* filename to avoid the collision, so the document ends up with two files
    ///   carrying the same identifier. The next scan picks one of them arbitrarily, and half the
    ///   time that is the stale one replacing the user's current text.
    /// - A leftover file for a document deleted or trashed while the setting was off still names
    ///   that document, so the first scan reads it as an edit and brings the document back.
    /// - A file edited in the folder while nothing was watching would be overwritten without a
    ///   word. It still loses to the app — there is no way to know which the user meant — but it
    ///   goes to the Trash first, so it is recoverable rather than gone.
    ///
    /// Files with no identifier are never touched: those are the user's own notes, and the first
    /// scan adopts them as documents.
    func reconcile(documents: [DocumentContent], spaces: [Space]) -> ReconcileResult {
        var result = ReconcileResult()
        // Every space gets a folder here, including empty ones. This is the only place that
        // creates them wholesale, and it is safe precisely because it is a migration: the app is
        // the authority on what exists at the moment the setting is turned on.
        createSpaceFolders(spaces: spaces)

        let existing = fileIndex()
        let live = Dictionary(
            documents.filter { !$0.isTrashed }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (id, url) in existing {
            guard let document = live[id] else {
                // Claimed by nothing: deleted or trashed while the setting was off.
                retire(url, into: &result)
                continue
            }
            if divergesFromDisk(document, at: url) {
                retire(url, into: &result)
            }
        }

        // `existing` is still used for placement: a retired file leaves its path free, and
        // writing the document back to that same path is what keeps a name the user chose.
        result.export = export(documents: documents, spaces: spaces, reusing: existing)
        return result
    }

    /// Whether the file says something different from the document.
    ///
    /// A file that cannot be parsed counts as divergent: it is not what we would write, and
    /// preserving it costs one item in the Trash.
    private func divergesFromDisk(_ document: DocumentContent, at url: URL) -> Bool {
        guard let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard let parsed = MarkdownDocumentFile.content(from: onDisk) else { return true }
        return ExternalChangePlanner.differs(parsed, from: document)
    }

    private func retire(_ url: URL, into result: inout ReconcileResult) {
        do {
            echoFilter?.forget(url)
            try retireFile(url)
            result.retiredFiles.append(url)
        } catch {
            // Failing to retire is not failing to migrate: the export still runs, and the worst
            // case is a leftover file the next scan reports as naming no document.
            logger.error("Could not retire a leftover file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves the whole folder to the Trash, for turning the setting off.
    ///
    /// The Trash rather than deletion: these are files in the user's Documents folder, and the
    /// one thing worse than leaving them behind is destroying them.
    func retireRoot() throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try retireFile(rootURL)
    }

    /// Where a document's file belongs, preferring the file it already occupies.
    ///
    /// A document that moves between spaces keeps its filename and changes directory —
    /// the file is the user's to name, the folder is ours to place.
    private func destination(
        for content: DocumentContent,
        in directory: URL,
        current: URL?
    ) -> URL {
        if let current {
            return current.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
                ? current
                : directory.appendingPathComponent(current.lastPathComponent)
        }

        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        return directory.appendingPathComponent(
            DocumentFilename.filename(for: WritingDocument(content: content, derived: nil), avoiding: taken)
        )
    }

    /// Which file each document currently occupies.
    ///
    /// One pass over the folder rather than a search per document: the naive version is
    /// quadratic and this runs on every save.
    func fileIndex() -> [UUID: URL] {
        var index: [UUID: URL] = [:]
        for url in markdownFiles() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  let id = MarkdownDocumentFile.identifier(in: contents)
            else { continue }
            // First writer wins, so a duplicated file cannot steal an identifier from the
            // original on an arbitrary enumeration order.
            if index[id] == nil {
                index[id] = url
            }
        }
        return index
    }

    /// Reads a written file back and confirms it says what the document says.
    private func verify(_ content: DocumentContent, at url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let readBack = MarkdownDocumentFile.content(from: contents) else {
            throw VerificationError.unreadable
        }
        guard readBack.id == content.id else { throw VerificationError.identifierMismatch }
        guard readBack.title == content.title else { throw VerificationError.titleMismatch }
        guard readBack.body == content.body else { throw VerificationError.bodyMismatch }
    }

    private enum VerificationError: LocalizedError {
        case unreadable, identifierMismatch, titleMismatch, bodyMismatch

        var errorDescription: String? {
            switch self {
            case .unreadable: "The written file could not be read back"
            case .identifierMismatch: "The written file has a different identifier"
            case .titleMismatch: "The written file has a different title"
            case .bodyMismatch: "The written file has different text"
            }
        }
    }

    /// Writes `_space.md` into folders that **already exist**, and creates none.
    ///
    /// Creating them here is what made a folder deleted in Finder come straight back: this runs
    /// on every save and every scan, so the deletion was undone before the user could look away
    /// — and undone as an *empty* folder, because the documents inside it were correctly
    /// trashed. Folders are created only where a folder is genuinely wanted: a full migration,
    /// a space created in the app, or a document being filed into one.
    private func writeSpaceFiles(
        spaces: [Space],
        allSpaces: [Space]? = nil,
        into _: inout ExportResult
    ) {
        for space in spaces {
            let directory = folderURL(forSpace: space.id, in: allSpaces ?? spaces)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            write(SpaceFile.render(space), toSpaceFileIn: directory)
        }
    }

    private func write(_ rendered: String, toSpaceFileIn directory: URL) {
        let url = directory.appendingPathComponent(SpaceFile.filename)
        do {
            echoFilter?.expect(rendered, at: url)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // A space file that cannot be written costs the folder its identity, which degrades
            // a later rename into a delete-and-create. Bad, but not worth failing a save over.
            logger.error("Could not write a space file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Space folders

    func folderURL(forSpace spaceID: UUID?, in spaces: [Space]) -> URL {
        rootURL.appendingPathComponent(
            SpaceFolderLayout.directoryComponents(forSpace: spaceID, in: spaces).joined(separator: "/")
        )
    }

    /// Which folder each space occupies, found by the identifier inside its `_space.md`.
    ///
    /// By identifier rather than by name, because a name can be changed on either side and the
    /// identifier cannot. It is also how a space with no folder at all is recognised — which is
    /// how a folder deleted outside the app is noticed.
    func spaceFolderIndex() -> [UUID: [String]] {
        var index: [UUID: [String]] = [:]
        for url in markdownFiles() where SpaceFile.isSpaceFile(filename: url.lastPathComponent) {
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  let identity = SpaceFile.identity(from: contents)
            else { continue }
            let components = relativeComponents(ofDirectory: url.deletingLastPathComponent())
            guard !components.isEmpty, index[identity.id] == nil else { continue }
            index[identity.id] = components
        }
        return index
    }

    /// Creates a folder for every space, for the migration that turns the setting on.
    func createSpaceFolders(spaces: [Space]) {
        for space in spaces {
            do {
                try createFolder(for: space, in: spaces)
            } catch {
                // Its documents land at the root instead, which is recoverable — unlike failing
                // the migration and leaving the user with nothing.
                logger.error("Could not create a space folder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Creates a space's folder and writes its identity, for a space made in the app.
    func createFolder(for space: Space, in spaces: [Space]) throws {
        let directory = folderURL(forSpace: space.id, in: spaces)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(SpaceFile.render(space), toSpaceFileIn: directory)
    }

    /// Moves a space's folder, for a space renamed or re-parented in the app.
    ///
    /// The identity is rewritten afterwards so the moved folder still names its space.
    func moveFolder(from components: [String], for space: Space, in spaces: [Space]) throws {
        let source = rootURL.appendingPathComponent(components.joined(separator: "/"))
        let destination = folderURL(forSpace: space.id, in: spaces)
        guard source.standardizedFileURL != destination.standardizedFileURL,
              FileManager.default.fileExists(atPath: source.path)
        else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        write(SpaceFile.render(space), toSpaceFileIn: destination)
    }

    /// Moves a space's folder to the Trash, for a space deleted in the app.
    ///
    /// A folder that is already gone is not an error — that is the case where the deletion came
    /// *from* the folder being removed in the first place.
    func retireFolder(at components: [String]) throws {
        guard !components.isEmpty else { return }
        let directory = rootURL.appendingPathComponent(components.joined(separator: "/"))
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try retireFile(directory)
    }

    // MARK: - Import

    /// Reads every document from the folder.
    func importAll(knownSpaces: [Space]) -> ImportResult {
        var result = ImportResult()

        for url in markdownFiles() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

            // Space files describe folders, never documents.
            if SpaceFile.isSpaceFile(filename: url.lastPathComponent)
                || SpaceFile.isSpaceFile(contents: contents)
            {
                continue
            }

            guard var content = MarkdownDocumentFile.content(from: contents) else {
                result.unidentifiedFiles.append(url)
                continue
            }

            // The folder is the authority on placement.
            content.spaceID = SpaceFolderLayout.spaceID(
                forDirectoryComponents: directoryComponents(of: url), in: knownSpaces
            )
            result.documents.append(content)
        }

        return result
    }

    // MARK: - Adoption

    /// Turns a markdown file that Logue has never seen into a document.
    ///
    /// The identifier is written back **into the same file**, keeping its name. Without
    /// that, the next scan would not recognise the file and would adopt it again, so a
    /// dropped-in note would multiply on every rescan. Keeping the name matters too: the
    /// user chose it, and this is a folder they were invited to work in.
    ///
    /// Returns `nil` if the file cannot be read or the identifier cannot be written —
    /// adopting a document whose file does not record its identity would produce exactly
    /// the duplication this avoids.
    func adopt(fileAt url: URL, knownSpaces: [Space]) -> DocumentContent? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        guard let fields = DroppedFileImport.fields(
            fileContents: contents, filename: url.lastPathComponent
        )
        else { return nil }

        var content = WritingDocument().content
        content.title = fields.title
        content.body = fields.body
        content.tags = fields.tags
        content.spaceID = SpaceFolderLayout.spaceID(
            forDirectoryComponents: directoryComponents(of: url), in: knownSpaces
        )

        do {
            let rendered = MarkdownDocumentFile.render(content)
            echoFilter?.expect(rendered, at: url)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Could not claim a dropped-in file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return content
    }

    /// Every `.md` file under the root, skipping hidden directories so a `.git` folder is
    /// never walked.
    func markdownFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == DocumentFilename.fileExtension }
    }

    /// Every directory under the root, as components relative to it.
    ///
    /// Includes empty ones: a folder someone made in Finder and has not put anything in yet
    /// is still a space they created.
    func directories() -> [[String]] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { relativeComponents(ofDirectory: $0) }
            .filter { !$0.isEmpty }
    }

    /// The identity a folder's `_space.md` claims, if it has one.
    func spaceIdentity(atDirectoryComponents components: [String]) -> SpaceFile.Identity? {
        let url = rootURL
            .appendingPathComponent(components.joined(separator: "/"))
            .appendingPathComponent(SpaceFile.filename)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return SpaceFile.identity(from: contents)
    }

    /// Writes `_space.md` for spaces that already have a folder, so a folder created outside
    /// the app gains an identity and can be renamed later without becoming a different space.
    ///
    /// `among` is the full space list, needed to work out where each folder lives; `spaces` is
    /// the subset to write. They differ when only one space has changed.
    func writeSpaceIdentities(spaces: [Space], among all: [Space]? = nil) {
        var ignored = ExportResult()
        writeSpaceFiles(spaces: spaces, allSpaces: all ?? spaces, into: &ignored)
    }

    /// Directory components of a file, relative to the root.
    ///
    /// Symlinks are resolved on **both** sides before comparing. `FileManager`'s enumerator
    /// hands back resolved paths, so a root spelled `/var/…` and a file spelled
    /// `/private/var/…` disagree by one component — and dropping the wrong number of them
    /// silently produces a path that names the root folder as a space. That is not a
    /// hypothetical: it is what this method did until an end-to-end test on a real temporary
    /// directory caught it.
    ///
    /// A file that is not under the root at all yields no components rather than a
    /// nonsensical path.
    func directoryComponents(of file: URL) -> [String] {
        relativeComponents(ofDirectory: file.deletingLastPathComponent())
    }

    /// Components of a directory relative to the root.
    ///
    /// Takes the directory itself rather than a file inside it: symlinks only resolve for
    /// paths that exist, so resolving `…/Work/does-not-exist.md` would leave the whole path
    /// unresolved while the root resolved — the same off-by-one from the other direction.
    func relativeComponents(ofDirectory directory: URL) -> [String] {
        let rootParts = rootURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let parts = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents

        guard parts.count > rootParts.count,
              Array(parts.prefix(rootParts.count)) == rootParts
        else { return [] }

        return Array(parts.dropFirst(rootParts.count))
    }
}
