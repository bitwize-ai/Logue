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

    init(rootURL: URL, echoFilter: WriteEchoFilter? = nil) {
        self.rootURL = rootURL
        self.echoFilter = echoFilter
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
                if name.hasSuffix(".\(MirrorFilename.fileExtension)") {
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

        writeSpaceFiles(spaces: spaces, into: &result)

        for content in documents where !content.isTrashed {
            let directory = rootURL.appendingPathComponent(
                MirrorLayout.directoryComponents(forSpace: content.spaceID, in: spaces)
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

        return result
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
            MirrorFilename.filename(for: WritingDocument(content: content, derived: nil), avoiding: taken)
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

    private func writeSpaceFiles(spaces: [Space], into result: inout ExportResult) {
        for space in spaces {
            let directory = rootURL.appendingPathComponent(
                MirrorLayout.directoryComponents(forSpace: space.id, in: spaces)
                    .joined(separator: "/")
            )
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let spaceFileURL = directory.appendingPathComponent(SpaceFile.filename)
                let rendered = SpaceFile.render(space)
                echoFilter?.expect(rendered, at: spaceFileURL)
                try rendered.write(to: spaceFileURL, atomically: true, encoding: .utf8)
            } catch {
                // A space folder that cannot be written is logged but does not fail the
                // whole migration: its documents will land at the root, which is
                // recoverable, unlike losing them.
                logger.error("Could not write a space file: \(error.localizedDescription, privacy: .public)")
            }
        }
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
            content.spaceID = MirrorLayout.spaceID(
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

        let plan = MirrorImportPlan.plan(
            fileContents: contents, filename: url.lastPathComponent, knownDocumentIDs: []
        )
        guard case let .importAsNew(title, body, tags) = plan else { return nil }

        var content = WritingDocument().content
        content.title = title
        content.body = body
        content.tags = tags
        content.spaceID = MirrorLayout.spaceID(
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
            .filter { $0.pathExtension == MirrorFilename.fileExtension }
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

    /// Writes `_space.md` for every space, so folders created outside the app gain an
    /// identity and can be renamed without becoming a different space.
    func writeSpaceIdentities(spaces: [Space]) {
        var ignored = ExportResult()
        writeSpaceFiles(spaces: spaces, into: &ignored)
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
