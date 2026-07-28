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
                logger.warning("Import skipped \(name, privacy: .public): \(reason, privacy: .public)")
            } catch {
                outcome.skipped.append(
                    ImportOutcome.Skipped(file: name, reason: "could not be read")
                )
                logger.error(
                    "Import failed to read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        logger.info("Imported \(outcome.imported) of \(urls.count) file(s)")
        return outcome
    }

    /// Reads a text file, tolerating the encodings exported notes actually use.
    /// UTF-8 first (every modern exporter), then UTF-16 (some Windows tools),
    /// then Latin-1, which cannot fail and at worst mangles exotic bytes visibly.
    private func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding: String.Encoding in [.utf8, .utf16, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
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
