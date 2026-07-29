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
    /// The folder, with symlinks resolved.
    ///
    /// Resolved because `FileManager.enumerator(at:)` does **not** follow a symlinked root: it walks
    /// the link itself and yields nothing, while `fileExists` follows it and reports the folder
    /// present. That combination read as "the folder is there and every document was deleted".
    /// Pointing this folder at an Obsidian vault or a synced directory is the most obvious use of the
    /// feature, so it has to work rather than be refused.
    let rootURL: URL

    /// How a file that no longer belongs is disposed of.
    ///
    /// The Trash rather than deletion, so anything retired on the user's behalf is one
    /// "Put Back" away. Injectable only so a test run does not fill the real Trash.
    let retireFile: @Sendable (URL) throws -> Void

    init(
        rootURL: URL,
        retireFile: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.rootURL = rootURL.resolvingSymlinksInPath()
        self.retireFile = retireFile
    }

    // Extension-visible: +SpaceFolders
    var logger: Logger {
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
        /// False when the walk could not read part of the folder. A caller must not treat a partial
        /// walk as evidence that anything was deleted.
        var isComplete = true
        /// Identifiers carried by more than one file. Nothing is applied for these: with two files
        /// claiming one document there is no way to know which the user means, and picking wrongly
        /// replaces their current text with an older copy.
        var ambiguousIdentifiers: Set<UUID> = []
        /// Documents whose file is present but could not be read on this pass. Absence from the
        /// results is therefore not evidence they were deleted.
        var unreadableIdentifiers: Set<UUID> = []
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
            // A directory we cannot list is not an empty directory. Swallowing the error made an
            // unreadable folder look safe to adopt, which is the opposite of true.
            let entries: [String]
            do {
                entries = try manager.contentsOfDirectory(atPath: rootURL.path)
            } catch {
                throw PrepareError.couldNotCreateRoot(
                    "the folder already there could not be read: \(error.localizedDescription)"
                )
            }
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
    /// `identitiesFor` limits which spaces get their `_space.md` rewritten. Defaults to all of them,
    /// which is right for a migration and wasteful for a single save.
    func export(
        documents: [DocumentContent],
        spaces: [Space],
        reusing existing: [UUID: URL] = [:],
        folders: SpaceFolderMap? = nil,
        identitiesFor identities: [Space]? = nil
    ) -> ExportResult {
        var result = ExportResult()
        // One walk, reused for every document: a space's folder is wherever the folder claiming it
        // actually is, which is not always where its name says it should be.
        let folders = folders ?? spaceFolderMap(in: spaces)

        for content in documents where !content.isTrashed {
            let directory = folderURL(forSpace: content.spaceID, in: spaces, folders: folders)
            let current = existing[content.id]
            let url = destination(for: content, in: directory, current: current)

            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let rendered = MarkdownDocumentFile.render(content)
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
        // The same map as above, not a second walk of the tree. `spaceFolderMap` is built purely
        // from the `_space.md` files a snapshot found, and the loop above creates directories
        // only — never an identity file — so re-reading here could not have returned anything
        // different. It did cost a full traversal per saved document, which a bulk import pays
        // once per file.
        writeSpaceFiles(
            spaces: identities ?? spaces,
            allSpaces: spaces,
            folders: folders,
            into: &result
        )

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
        // Unreadable follows the same rule as unparseable, which this method already documents: it is
        // not what we would write, so it is preserved. Returning false meant "does not diverge", so
        // an unreadable file was silently overwritten by the export a few lines later.
        guard let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return true }
        guard let parsed = MarkdownDocumentFile.content(from: onDisk) else { return true }
        return ExternalChangePlanner.differs(parsed, from: document)
    }

    private func retire(_ url: URL, into result: inout ReconcileResult) {
        do {
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
        if let current, current.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            return current
        }

        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])

        // Moving between folders keeps the name the user gave the file — unless something in the
        // destination already has it. Writing there anyway would overwrite a different document's
        // file, and the next scan would find that document fileless and trash it. Compared
        // case-insensitively, and confirmed against the filesystem, because the fold is the
        // filesystem's to decide and not ours to predict.
        if let current {
            let name = current.lastPathComponent
            let collides = taken.contains { $0.lowercased() == name.lowercased() }
                || FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
            if !collides {
                return directory.appendingPathComponent(name)
            }
        }
        return directory.appendingPathComponent(
            DocumentFilename.filename(for: WritingDocument(content: content, derived: nil), avoiding: taken)
        )
    }

    /// Which file each document currently occupies.
    ///
    /// One pass over the folder rather than a search per document: the naive version is
    /// quadratic and this runs on every save.
    func fileIndex(using snapshot: FolderSnapshot? = nil) -> [UUID: URL] {
        documentFiles(using: snapshot).byID
    }

    /// The file each document occupies, plus the copies that lost.
    ///
    /// Duplicates are returned rather than dropped: a second file carrying a document's identifier
    /// is invisible to the user and never written to again, so something has to be able to say so.
    func documentFiles(using snapshot: FolderSnapshot? = nil) -> (byID: [UUID: URL], duplicates: [URL]) {
        let snapshot = snapshot ?? self.snapshot()
        var index: [UUID: URL] = [:]
        var duplicates: [URL] = []
        for url in snapshot.files {
            guard let contents = snapshot.contents[url],
                  let id = MarkdownDocumentFile.identifier(in: contents)
            else { continue }
            // First in sorted order wins, so a duplicated file cannot take an identifier from the
            // file the rest of the app is using: every pass makes the same choice.
            if index[id] == nil {
                index[id] = url
            } else {
                duplicates.append(url)
            }
        }
        return (index, duplicates)
    }

    /// Reads a written file back and confirms it says what the document says.
    ///
    /// Compares **everything the file is supposed to carry**, not three fields of fifteen. The narrow
    /// version is what let four separate bugs pass verification and flip the mode with confidence:
    /// typed properties flattening to text, `organised` coming back `false` instead of `nil`,
    /// `goalMode` never being written at all, and a custom property named `title` shadowing the real
    /// one. Anything this does not inspect can be destroyed by the round trip and still "verify".
    ///
    /// `modifiedAt` is excluded deliberately — it is read from the file's own timestamp — and
    /// `isTrashed` is excluded because a trashed document has no file by design.
    private func verify(_ content: DocumentContent, at url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let readBack = MarkdownDocumentFile.content(from: contents) else {
            throw VerificationError.unreadable
        }
        guard readBack.id == content.id else { throw VerificationError.identifierMismatch }
        guard readBack.title == content.title else { throw VerificationError.titleMismatch }
        guard readBack.body == content.body else { throw VerificationError.bodyMismatch }

        guard readBack.tags == content.tags else { throw VerificationError.fieldMismatch("tags") }
        guard readBack.icon == content.icon else { throw VerificationError.fieldMismatch("icon") }
        guard readBack.goalMode == content.goalMode else {
            throw VerificationError.fieldMismatch("goal")
        }
        guard readBack.isPinned == content.isPinned else {
            throw VerificationError.fieldMismatch("pinned")
        }
        guard readBack.storedIsOrganised == content.storedIsOrganised else {
            throw VerificationError.fieldMismatch("organised")
        }
        guard readBack.storedWidthMode == content.storedWidthMode else {
            throw VerificationError.fieldMismatch("width")
        }
        guard readBack.properties ?? [:] == content.properties ?? [:] else {
            throw VerificationError.fieldMismatch("properties")
        }
        guard readBack.relationships ?? [:] == content.relationships ?? [:] else {
            throw VerificationError.fieldMismatch("relationships")
        }
        // Seconds, because the file stores an ISO-8601 string and the in-memory value has
        // sub-second precision the format does not carry.
        guard abs(readBack.createdAt.timeIntervalSince(content.createdAt)) < 1 else {
            throw VerificationError.fieldMismatch("created")
        }
    }

    private enum VerificationError: LocalizedError {
        case unreadable, identifierMismatch, titleMismatch, bodyMismatch
        case fieldMismatch(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "The written file could not be read back"
            case .identifierMismatch: "The written file has a different identifier"
            case .titleMismatch: "The written file has a different title"
            case .bodyMismatch: "The written file has different text"
            case let .fieldMismatch(field): "The written file lost or changed “\(field)”"
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
        folders: SpaceFolderMap? = nil,
        into _: inout ExportResult
    ) {
        let all = allSpaces ?? spaces
        let folders = folders ?? spaceFolderMap(in: all)

        for space in spaces {
            let directory = folderURL(forSpace: space.id, in: all, folders: folders)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            writeIdentity(of: space, in: directory)
        }
    }

    /// Writes a space's identity, keeping any prose already in the file.
    ///
    /// Extension-visible: +SpaceFolders
    func writeIdentity(of space: Space, in directory: URL) {
        let url = directory.appendingPathComponent(SpaceFile.filename)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        write(SpaceFile.render(space, keepingBodyOf: existing), toSpaceFileIn: directory)
    }

    private func write(_ rendered: String, toSpaceFileIn directory: URL) {
        let url = directory.appendingPathComponent(SpaceFile.filename)
        do {
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // A space file that cannot be written costs the folder its identity, which degrades
            // a later rename into a delete-and-create. Bad, but not worth failing a save over.
            logger.error("Could not write a space file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Import

    /// Reads every document from the folder.
    func importAll(
        knownSpaces: [Space],
        folders: SpaceFolderMap? = nil,
        using snapshot: FolderSnapshot? = nil
    ) -> ImportResult {
        var result = ImportResult()
        let snapshot = snapshot ?? self.snapshot()
        let folders = folders ?? spaceFolderMap(in: knownSpaces, using: snapshot)
        var seenIdentifiers: Set<UUID> = []

        result.isComplete = snapshot.isComplete

        for url in snapshot.files {
            guard let contents = snapshot.contents[url] else {
                // Unreadable is not absent. Recording it keeps the document out of the deletion set,
                // and one more read here is worth it: the snapshot could not get the contents, but the
                // identifier is what decides whether a document is about to be trashed.
                if let id = identifierIfReadable(at: url) {
                    result.unreadableIdentifiers.insert(id)
                }
                continue
            }

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

            // The file's own timestamp, because nothing in the markdown records one an outside editor
            // would update. Without this every import stamped the whole library with the launch time,
            // so "Recent" was in an arbitrary order and switching the setting off wrote those
            // invented dates into encrypted storage for good.
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            {
                content.modifiedAt = modified
            }

            guard seenIdentifiers.insert(content.id).inserted else {
                result.ambiguousIdentifiers.insert(content.id)
                continue
            }

            // The folder is the authority on placement, and which space a folder *is* comes from
            // the identity inside it rather than from its name.
            content.spaceID = folders.spaceID(
                forComponents: directoryComponents(of: url, using: snapshot), in: knownSpaces
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
        // Carried through because the render below writes back over the user's file: a `created:`
        // or a `status:` this dropped would not just be missing from the library, it would be gone
        // from disk.
        if let createdAt = fields.createdAt {
            content.createdAt = createdAt
        }
        if !fields.properties.isEmpty {
            content.properties = fields.properties
        }
        content.spaceID = spaceFolderMap(in: knownSpaces).spaceID(
            forComponents: directoryComponents(of: url), in: knownSpaces
        )

        do {
            let rendered = MarkdownDocumentFile.render(content)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Could not claim a dropped-in file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return content
    }

    /// The identifier a file claims, when the file can be read at all.
    private func identifierIfReadable(at url: URL) -> UUID? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return MarkdownDocumentFile.identifier(in: contents)
    }

    /// Whether each of these documents still has a file on disk, checked directly.
    ///
    /// Deliberately not a walk: this is the cross-check *against* the walk, so it has to ask the
    /// filesystem about each path rather than trusting the same traversal that may have failed.
    func documentsStillOnDisk(_ index: [UUID: URL]) -> Set<UUID> {
        var present: Set<UUID> = []
        for (id, url) in index where FileManager.default.fileExists(atPath: url.path) {
            present.insert(id)
        }
        return present
    }

    /// Every `.md` file under the root, skipping hidden directories so a `.git` folder is
    /// never walked.
    func markdownFiles(using snapshot: FolderSnapshot? = nil) -> [URL] {
        (snapshot ?? self.snapshot()).files
    }

    /// The walk, and whether it completed. A view over `snapshot()`.
    func walk() -> (files: [URL], isComplete: Bool) {
        let snapshot = snapshot()
        return (snapshot.files, snapshot.isComplete)
    }

    /// Every directory under the root, as components relative to it.
    ///
    /// Includes empty ones: a folder someone made in Finder and has not put anything in yet
    /// is still a space they created.
    func directories(using snapshot: FolderSnapshot? = nil) -> [[String]] {
        (snapshot ?? self.snapshot()).directories
    }

    /// Reads the folder once, for every question a scan needs to ask of it.
    ///
    /// Files and directories come from the same enumeration, and each file's contents are read here
    /// rather than again by whoever asks next. See `FolderSnapshot` for why this exists.
    func snapshot() -> FolderSnapshot {
        var failures = 0
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                failures += 1
                Logger(subsystem: AppConstants.bundleID, category: "MarkdownStorageMigrator").error(
                    "Could not read \(url.lastPathComponent, privacy: .public) while walking: \(error.localizedDescription, privacy: .public)"
                )
                // Keep going, so one unreadable corner does not hide the rest — but the caller is
                // told the walk was partial.
                return true
            }
        )
        else { return FolderSnapshot(isComplete: false) }

        var files: [URL] = []
        var directories: [[String]] = []

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let components = relativeComponents(ofDirectory: url)
                if !components.isEmpty {
                    directories.append(components)
                }
                continue
            }
            if url.pathExtension == DocumentFilename.fileExtension {
                files.append(url)
            }
        }

        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var contents: [URL: String] = [:]
        var componentsByFile: [URL: [String]] = [:]
        var unreadable = 0
        for url in files {
            componentsByFile[url] = relativeComponents(ofDirectory: url.deletingLastPathComponent())
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                contents[url] = text
            } else {
                // A file that is there but unreadable is not an absent file, and the difference
                // decides whether its document gets trashed.
                unreadable += 1
            }
        }

        return FolderSnapshot(
            files: files,
            directories: directories,
            contents: contents,
            componentsByFile: componentsByFile,
            isComplete: failures == 0 && unreadable == 0
        )
    }

    /// The identity a folder's `_space.md` claims, if it has one.
    func spaceIdentity(
        atDirectoryComponents components: [String],
        using snapshot: FolderSnapshot? = nil
    ) -> SpaceFile.Identity? {
        let url = rootURL
            .appendingPathComponent(components.joined(separator: "/"))
            .appendingPathComponent(SpaceFile.filename)

        guard let contents = snapshot?.contents[url]
            ?? (try? String(contentsOf: url, encoding: .utf8))
        else { return nil }
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
    func directoryComponents(of file: URL, using snapshot: FolderSnapshot? = nil) -> [String] {
        if let frozen = snapshot?.componentsByFile[file] {
            return frozen
        }
        return relativeComponents(ofDirectory: file.deletingLastPathComponent())
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
