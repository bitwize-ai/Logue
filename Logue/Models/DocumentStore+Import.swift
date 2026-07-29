import Foundation
import os.log

/// Importing external note files (issue #28).
///
/// Reading and document creation only — deriving a title and body from file
/// contents is `MarkdownImport`'s job, so it stays testable without a store.
extension DocumentStore {
    /// What happened to each file of an import, for user-facing feedback.
    struct ImportOutcome {
        struct Skipped {
            let file: String
            let reason: String
        }

        var imported = 0
        var skipped: [Skipped] = []
        /// Set when a limit stopped the walk before it finished, so the report can say the folder
        /// was only partly read rather than implying it was all of it.
        var stoppedEarly: String?
        /// Set when the user cancelled. Nothing was created.
        var wasCancelled = false
    }

    /// Imports the given files as documents, optionally into a space.
    ///
    /// Each file is handled independently: one unreadable or empty file is
    /// reported in the outcome and never aborts the rest. Nothing is selected
    /// automatically — a bulk import jumping the editor to an arbitrary file
    /// would be disorienting.
    ///
    /// Reading and parsing happen off the main actor. A vault's worth of files on
    /// a slow or network volume would otherwise block the main thread for as long
    /// as the reads took, with no way to tell the app was still alive.
    /// A vault is a tree, so a chosen directory is walked and its subfolders become sub-spaces.
    /// A chosen file lands directly in `spaceID`.
    @discardableResult
    func importFiles(at urls: [URL], into spaceID: UUID?) async -> ImportOutcome {
        let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")

        // Expanding directories, partitioning already-stored files, and reading are all one
        // detached pass. Every step of it touches the filesystem, and a vault on a network volume
        // makes that a wait the main actor must not be holding.
        let storedRoot = Self.storedRootPath
        // Derived from how deep a space can be, minus where this one already sits. A folder deeper
        // than that has no representable path, and `SpaceFolderLayout` answers "no path" with the
        // markdown root — which would put a subfolder's `_space.md` and documents in `~/Logue`.
        let limits = Self.limits(forDestination: spaceID)
        let scanned = await Task.detached(priority: .userInitiated) {
            Self.collect(from: urls, storedRoot: storedRoot, limits: limits)
        }.value

        var outcome = ImportOutcome()
        outcome.skipped = scanned.skipped
        outcome.stoppedEarly = scanned.stoppedEarly

        // Nothing is created from a cancelled walk. A partial vault is worse than none: there is no
        // bulk undo, so the user would be left picking imported notes out by hand.
        guard !scanned.wasCancelled, !Task.isCancelled else {
            outcome.wasCancelled = true
            return outcome
        }

        // Re-checked after the await, not only by the caller before it. Reading a batch off a
        // network volume takes long enough for the user to delete the space in the meantime, and
        // the panel stays open throughout; documents filed against a dead id have no sidebar row.
        var destination = spaceID
        if let spaceID, SpaceStore.shared.space(for: spaceID) == nil {
            logger.warning("Import target space no longer exists — filing at the top level")
            destination = nil
        }

        // Grouped by the folder each file came from, so one pass creates one space and the
        // documents under it. The empty path is the top level of the selection.
        for path in scanned.files.keys.sorted(by: { $0.joined(separator: "/") < $1.joined(separator: "/") }) {
            // Creating documents is synchronous and this method is main-actor, so without a yield
            // the batch ran as one uninterrupted turn: SwiftUI could not draw a frame until the
            // last file was done, which is a beachball with no spinner and nothing to cancel.
            await Task.yield()
            guard !Task.isCancelled else {
                outcome.wasCancelled = true
                return outcome
            }

            guard let group = scanned.files[path] else { continue }
            let target = path.isEmpty ? destination : spaceFor(path: path, under: destination)

            var drafts: [DocumentDraft] = []
            for file in group {
                switch file.result {
                case let .success(document):
                    drafts.append(DocumentDraft(
                        title: document.title,
                        body: document.body,
                        tags: document.tags,
                        createdAt: document.createdAt,
                        modifiedAt: document.modifiedAt,
                        properties: document.properties
                    ))
                case let .failure(error):
                    outcome.skipped.append(ImportOutcome.Skipped(
                        file: file.name, reason: Self.reason(for: error)
                    ))
                    // The underlying error too: everything that is not an ImportError collapses to
                    // one reason, and without this a report of "it skipped 40 files" cannot be
                    // diagnosed at all.
                    logger.warning(
                        """
                        Import skipped \(file.name, privacy: .private): \
                        \(Self.reason(for: error), privacy: .public) \
                        (\(error.localizedDescription, privacy: .public))
                        """
                    )
                }
            }

            await createDocuments(drafts, inSpace: target)
            outcome.imported += drafts.count
        }

        logger.info("Imported \(outcome.imported) document(s) from \(urls.count) selected item(s)")
        return outcome
    }

    /// How much one import may take on, and how deep it may nest.
    ///
    /// The depth allowance is what is left of `SpaceFolderLayout.maxDepth` after the destination
    /// space's own depth. Importing a 12-deep vault into a space at depth 1 would otherwise create
    /// spaces at depths 2…13, and everything past the cap resolves to the markdown root.
    static func limits(forDestination spaceID: UUID?) -> ImportLimits {
        let depth = SpaceFolderLayout.directoryComponents(
            forSpace: spaceID, in: SpaceStore.shared.spaces
        ).count
        return ImportLimits(maxDepth: max(1, SpaceFolderLayout.maxDepth - depth))
    }

    /// The user-facing reason a file was not imported.
    ///
    /// Distinguishing these matters more than it looks: grouped reporting collapses a whole vault's
    /// failures into one line per reason, so "could not be read" for everything means a
    /// false-positive binary rejection is indistinguishable from a permissions problem.
    private static func reason(for error: Error) -> String {
        if let importError = error as? MarkdownImport.ImportError {
            return description(for: importError)
        }
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else { return "could not be read" }
        switch CocoaError.Code(rawValue: cocoa.code) {
        case .fileReadNoPermission:
            return "no permission to read it"
        case .fileReadNoSuchFile:
            return "the file was not there"
        case .fileReadInapplicableStringEncoding:
            return "not readable as text"
        case .fileReadUnknown:
            return "its size could not be read"
        default:
            return "could not be read"
        }
    }

    /// Finds or creates the space a folder path maps to, creating each level as it goes.
    ///
    /// Matched by name among siblings rather than created blindly, so importing the same vault
    /// twice does not produce `Projects` and `Projects (2)` side by side.
    private func spaceFor(path: [String], under root: UUID?) -> UUID? {
        let spaces = SpaceStore.shared
        var parent = root
        for component in path {
            let existing = spaces.spaces.first {
                $0.parentID == parent && $0.name.compare(component, options: [.caseInsensitive]) == .orderedSame
            }
            guard let next = existing ?? spaces.createSpace(name: component, parentID: parent) else {
                // Nothing more can be nested under a level that could not be made. Filing the rest
                // at the parent keeps the documents rather than dropping them on the floor.
                return parent
            }
            parent = next.id
        }
        return parent
    }

    /// One file read, with the folder path it should be filed under.
    struct ScannedFile {
        let name: String
        let result: Result<MarkdownImport.ImportedDocument, Error>
    }

    /// What a selection turned out to contain: files grouped by their folder path relative to the
    /// selection, plus everything refused before it was read.
    struct ScannedSelection {
        var files: [[String]: [ScannedFile]] = [:]
        var skipped: [ImportOutcome.Skipped] = []
        /// Set when a limit stopped the walk early, so the caller can say so rather than
        /// present a truncated result as the whole folder.
        var stoppedEarly: String?
        /// True when the walk was cancelled. Distinct from a limit: nothing should be imported.
        var wasCancelled = false

        var fileCount: Int {
            files.values.reduce(0) { $0 + $1.count }
        }
    }

    /// What one walk is allowed to take on.
    ///
    /// A folder chosen in an open panel is not a vault by construction — the panel opens wherever
    /// the user last was, and picking the home folder one click above the vault is a normal slip.
    /// Without these, that walk descends through checkouts, caches and `Library`, reads every
    /// matching file into memory, and then creates a space per directory: thousands of rows, no
    /// progress, and no bulk undo.
    struct ImportLimits {
        var maxFiles = 5000
        var maxTotalBytes = 256 * 1024 * 1024
        /// Relative depth allowed below the destination. Resolved by the caller from
        /// `SpaceFolderLayout.maxDepth`, because a folder deeper than a space can be is not a
        /// folder we can store.
        var maxDepth: Int

        static let unlimitedDepth = SpaceFolderLayout.maxDepth
    }

    /// Running totals the walk checks against `ImportLimits`.
    private struct WalkBudget {
        var files = 0
        var bytes = 0
        /// Directory identities already entered, so a symlink cycle terminates.
        ///
        /// `isDirectory` resolves symlinks, so a link pointing at an ancestor — or at `/` — reads
        /// as an ordinary directory and the walk re-enters it. Depth alone does not save us: N
        /// self-referential links give N^depth paths before the cap bites.
        var visited: Set<FileIdentity> = []
    }

    /// A directory's identity on disk, for cycle detection. Path is not identity — that is the
    /// whole point of a symlink.
    private struct FileIdentity: Hashable {
        let volume: Int
        let file: Int
    }

    /// Expands the selection into readable files, walking directories.
    ///
    /// `nonisolated` and pure filesystem work, so a vault on a slow volume is read off the main
    /// actor. Directories are walked rather than refused because a vault *is* a tree — importing
    /// one folder at a time, flattened into a single space, was the whole shape of the problem.
    ///
    /// A chosen directory contributes its own name as the first path component, so the folder
    /// becomes a space rather than having its contents tipped into the destination — and so two
    /// folders selected together stay two trees instead of merging wherever their subfolder names
    /// happen to agree.
    nonisolated static func collect(
        from urls: [URL], storedRoot: String?, limits: ImportLimits
    ) -> ScannedSelection {
        var scanned = ScannedSelection()
        var budget = WalkBudget()

        for url in urls {
            if Task.isCancelled {
                scanned.wasCancelled = true
                return scanned
            }
            if isDirectory(url) {
                walk(
                    url, relativeTo: [url.lastPathComponent], depth: 1,
                    storedRoot: storedRoot, limits: limits, budget: &budget, into: &scanned
                )
            } else {
                add(url, at: [], storedRoot: storedRoot, limits: limits, budget: &budget, into: &scanned)
            }
        }
        return scanned
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func walk(
        _ directory: URL,
        relativeTo path: [String],
        depth: Int,
        storedRoot: String?,
        limits: ImportLimits,
        budget: inout WalkBudget,
        into scanned: inout ScannedSelection
    ) {
        if Task.isCancelled {
            scanned.wasCancelled = true
            return
        }
        guard scanned.stoppedEarly == nil else { return }

        // Deeper than a space can be nested. `SpaceFolderLayout.directoryComponents` returns no
        // path at all past its cap, which resolves to the markdown root — so the folder's
        // `_space.md` and every document in it would be written straight into `~/Logue`, and the
        // next scan would read them as root-level and flatten the hierarchy away.
        guard depth <= limits.maxDepth else {
            scanned.skipped.append(ImportOutcome.Skipped(
                file: directory.lastPathComponent,
                reason: "nested deeper than \(limits.maxDepth) folders below the destination"
            ))
            return
        }

        guard let identity = identity(of: directory), budget.visited.insert(identity).inserted else {
            // Either unreadable, or already entered by another path — a symlink loop.
            return
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                // `.obsidian`, `.trash` and `.git` are configuration and history, not notes.
                options: [.skipsHiddenFiles]
            )
        } catch {
            scanned.skipped.append(ImportOutcome.Skipped(
                file: directory.lastPathComponent,
                reason: "folder could not be read (\(error.localizedDescription))"
            ))
            return
        }

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard scanned.stoppedEarly == nil, !scanned.wasCancelled else { return }
            if isDirectory(url) {
                walk(
                    url, relativeTo: path + [url.lastPathComponent], depth: depth + 1,
                    storedRoot: storedRoot, limits: limits, budget: &budget, into: &scanned
                )
            } else {
                add(url, at: path, storedRoot: storedRoot, limits: limits, budget: &budget, into: &scanned)
            }
        }
    }

    /// Reads one file into the selection, unless it is already ours or not a note at all.
    ///
    /// Files with an extension we do not import are passed over in silence when they were found by
    /// walking a folder — a vault is full of images and PDFs, and listing every one of them as
    /// "skipped" would bury the failures that matter. A file the user picked by hand is still
    /// reported, because they meant that one.
    nonisolated private static func add(
        _ url: URL,
        at path: [String],
        storedRoot: String?,
        limits: ImportLimits,
        budget: inout WalkBudget,
        into scanned: inout ScannedSelection
    ) {
        let name = url.lastPathComponent
        guard MarkdownImport.allowedExtensions.contains(url.pathExtension.lowercased()) else {
            if path.isEmpty {
                scanned.skipped.append(ImportOutcome.Skipped(file: name, reason: "not a markdown or text file"))
            }
            return
        }
        if let reason = alreadyStoredReason(for: url, storedRoot: storedRoot) {
            scanned.skipped.append(ImportOutcome.Skipped(file: name, reason: reason))
            return
        }

        // Counted before the read. Everything read is held in memory until the whole selection has
        // been walked, so the cap has to bound what is taken on, not what has already been taken.
        guard budget.files < limits.maxFiles else {
            scanned.stoppedEarly = "more than \(limits.maxFiles) files"
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard budget.bytes + size <= limits.maxTotalBytes else {
            scanned.stoppedEarly = "more than \(limits.maxTotalBytes / 1_048_576) MB of files"
            return
        }
        budget.files += 1
        budget.bytes += size

        scanned.files[path, default: []].append(ScannedFile(name: name, result: read(url)))
    }

    /// Whether the URL is a directory. Symlinks are resolved, which is why `walk` also tracks
    /// identity — a link to an ancestor reads as an ordinary directory here.
    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            // Not silent: an entry we cannot even stat is not a directory to descend into, and
            // saying so here is more useful than the "could not be read" it would earn as a file.
            Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                .warning("Import skipped an unreadable entry: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated private static func identity(of url: URL) -> FileIdentity? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeIdentifierKey, .fileResourceIdentifierKey])
            // Both are documented as opaque objects, comparable with `isEqual:` — so they are
            // bridged to `NSObject` for hashing rather than used directly.
            guard let volume = values.volumeIdentifier as? NSObject,
                  let file = values.fileResourceIdentifier as? NSObject
            else { return nil }
            return FileIdentity(volume: volume.hash, file: file.hash)
        } catch {
            Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                .warning("Import could not identify a folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reads and parses one file. `nonisolated` so a batch can run off the main
    /// actor; it touches no store state. Internal so a test can point it at a temp
    /// directory — it makes falsifiable claims about encodings that are worth asserting.
    nonisolated static func read(_ url: URL) -> Result<MarkdownImport.ImportedDocument, Error> {
        do {
            let contents = try readText(at: url)
            return try .success(MarkdownImport.document(fileName: url.lastPathComponent, contents: contents))
        } catch {
            return .failure(error)
        }
    }

    /// Reads a text file, tolerating the encodings exported notes actually use.
    ///
    /// The size is checked before reading: a multi-gigabyte file named `.md` would
    /// otherwise be held in memory twice, as `Data` and again as `String`, only to
    /// be rejected.
    ///
    /// UTF-16 is tried only when a byte-order mark says so. Without one it assumes
    /// big-endian and accepts almost any byte sequence, so a Latin-1 file would
    /// decode to plausible-looking CJK rather than falling through — `Café résumé`
    /// came back as `䍡曩⁲畭湡整潫`. Windows-1252 is the better guess for what UTF-8
    /// rejects, and Latin-1 is the backstop that cannot fail.
    ///
    /// Which is why the ladder is not the whole answer. Latin-1 maps every byte, so a `.dylib`
    /// renamed `.md` decodes rather than being rejected, and imports as mojibake full of NULs —
    /// and in markdown mode that gets written straight back out as a `.md` file. `looksLikeText`
    /// is the check that stops it.
    nonisolated static func readText(at url: URL) throws -> String {
        // A size we could not read is not a small one. Treating it as zero let exactly the file
        // this pre-check exists for — the one we cannot say anything about — be read whole into
        // memory anyway.
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        guard size <= MarkdownImport.maxFileBytes else {
            throw MarkdownImport.ImportError.fileTooLarge(bytes: size)
        }

        let data = try Data(contentsOf: url)
        var encodings: [String.Encoding] = [.utf8]
        if hasUTF16ByteOrderMark(data) {
            encodings.insert(.utf16, at: 0)
        }
        encodings.append(contentsOf: [.windowsCP1252, .isoLatin1])

        for encoding in encodings {
            guard let text = String(data: data, encoding: encoding) else { continue }
            guard looksLikeText(text) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// Whether decoded bytes are plausibly a text file rather than a binary that merely decoded.
    ///
    /// Two signals, both deliberately blunt. A NUL is decisive: no text encoding a person writes
    /// notes in produces one, and every binary format is full of them. Beyond that, a share of
    /// control characters above a few percent is the shape of a binary — a note that uses form
    /// feeds or an escape sequence stays well under it.
    ///
    /// Only the leading bytes are examined, because a binary announces itself immediately and the
    /// point of this check is to run before the file is turned into a document.
    nonisolated static func looksLikeText(_ text: String) -> Bool {
        let sample = text.unicodeScalars.prefix(4096)
        guard !sample.isEmpty else { return true }

        var controls = 0
        for scalar in sample {
            if scalar.value == 0 {
                return false
            }
            // Tab, newline and carriage return are text, whatever else `Cc` contains.
            if CharacterSet.controlCharacters.contains(scalar), scalar != "\t", scalar != "\n", scalar != "\r" {
                controls += 1
            }
        }
        // Both an absolute floor and a ratio. A bare ratio meant a single control character
        // rejected any file of 20 scalars or fewer, so a one-line note pasted from a terminal
        // ("Note\u{0C}more text") was refused outright — and 24 ANSI escapes in a pasted build
        // log tipped a 395-character note over, while the same paste surrounded by more prose
        // passed. Requiring both makes the small cases behave like the large ones.
        return controls <= 2 || Double(controls) / Double(sample.count) < 0.05
    }

    nonisolated private static func hasUTF16ByteOrderMark(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let first = data[data.startIndex]
        let second = data[data.index(after: data.startIndex)]
        return (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF)
    }

    /// Why a file should not be imported because the app already stores it, or `nil` when it is
    /// an ordinary outside file.
    ///
    /// In markdown mode the folder *is* the library, so a file inside it is already a document —
    /// or is about to be adopted as one by the next scan. Importing it would make a second
    /// document from the same text and leave the original to be adopted separately. Symlinks are
    /// resolved on both sides so an aliased path cannot slip past.
    /// The folder documents already live in, when markdown storage is on.
    ///
    /// Resolved on the main actor and handed to the walk, which is `nonisolated` so a vault on a
    /// slow volume is read off the main thread. Reading `DocumentStorage.shared` from inside the
    /// walk would put main-actor state on a background thread.
    static var storedRootPath: String? {
        guard DocumentStorage.shared.mode.isMarkdown else { return nil }
        return DocumentStorage.markdownRootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path.lowercased()
    }

    nonisolated private static func alreadyStoredReason(for url: URL, storedRoot: String?) -> String? {
        guard let storedRoot else { return nil }
        // Only `.md`, because that is all a scan adopts. Refusing a `.txt` sitting in the folder
        // would leave it importable by no route at all, under a message that is not even true.
        guard url.pathExtension.lowercased() == "md" else { return nil }

        // Compared case-insensitively: the default APFS volume is, so a path reached through a
        // differently-cased component would otherwise slip past and be imported twice.
        let file = url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        guard file.hasPrefix(storedRoot + "/") else { return nil }
        return "already in the Logue folder"
    }

    nonisolated private static func description(for error: MarkdownImport.ImportError) -> String {
        switch error {
        case .emptyFile:
            "file is empty"
        case let .unsupportedExtension(ext):
            ext.isEmpty ? "unsupported file type" : "unsupported file type .\(ext)"
        case .fileTooLarge:
            "larger than the \(MarkdownImport.maxFileBytes / 1_048_576) MB limit"
        }
    }
}
