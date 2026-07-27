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
    func export(documents: [DocumentContent], spaces: [Space]) -> ExportResult {
        var result = ExportResult()

        writeSpaceFiles(spaces: spaces, into: &result)

        for content in documents where !content.isTrashed {
            let directory = rootURL.appendingPathComponent(
                MirrorLayout.directoryComponents(forSpace: content.spaceID, in: spaces)
                    .joined(separator: "/")
            )
            let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            let url = directory.appendingPathComponent(
                MirrorFilename.filename(for: WritingDocument(content: content, derived: nil), avoiding: taken)
            )

            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let rendered = MarkdownDocumentFile.render(content)
                try rendered.write(to: url, atomically: true, encoding: .utf8)

                try verify(content, at: url)
                result.writtenFiles[content.id] = url
            } catch {
                result.failures[content.id] = error.localizedDescription
                logger.error("Export failed for one document: \(error.localizedDescription, privacy: .public)")
            }
        }

        return result
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
                try SpaceFile.render(space).write(
                    to: directory.appendingPathComponent(SpaceFile.filename),
                    atomically: true,
                    encoding: .utf8
                )
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

    /// Directory components of a file, relative to the root.
    func directoryComponents(of file: URL) -> [String] {
        let rootParts = rootURL.standardizedFileURL.pathComponents
        let fileParts = file.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileParts.count > rootParts.count else { return [] }
        return Array(fileParts.dropFirst(rootParts.count))
    }
}
