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
    }

    /// Imports the given files as documents, optionally into a space.
    ///
    /// Each file is handled independently: one unreadable or empty file is
    /// reported in the outcome and never aborts the rest. Nothing is selected
    /// automatically — a bulk import jumping the editor to an arbitrary file
    /// would be disorienting.
    @discardableResult
    func importFiles(at urls: [URL], into spaceID: UUID?) -> ImportOutcome {
        let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
        var outcome = ImportOutcome()

        for url in urls {
            let name = url.lastPathComponent
            do {
                let contents = try readText(at: url)
                let imported = try MarkdownImport.document(fileName: name, contents: contents)
                createDocument(
                    title: imported.title,
                    body: imported.body,
                    inSpace: spaceID,
                    select: false
                )
                outcome.imported += 1
            } catch let error as MarkdownImport.ImportError {
                let reason = description(for: error)
                outcome.skipped.append(ImportOutcome.Skipped(file: name, reason: reason))
                logger.warning("Import skipped \(name, privacy: .private): \(reason, privacy: .public)")
            } catch {
                outcome.skipped.append(
                    ImportOutcome.Skipped(file: name, reason: "could not be read")
                )
                logger.error(
                    "Import failed to read \(name, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        logger.info("Imported \(outcome.imported) of \(urls.count) file(s)")
        return outcome
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
    private func readText(at url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
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
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private func hasUTF16ByteOrderMark(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let first = data[data.startIndex]
        let second = data[data.index(after: data.startIndex)]
        return (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF)
    }

    private func description(for error: MarkdownImport.ImportError) -> String {
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
