import Foundation
import OSLog

// MARK: - Mode

/// How documents are stored on disk.
enum DocumentStorageMode: String, Codable, Sendable {
    /// Encrypted JSON in Application Support. The default.
    case encrypted
    /// Plain `.md` files in `~/Documents/Logue`, editable outside the app.
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
/// `~/Documents/Logue` to files a person would want to see.
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

    /// Where plain markdown documents live. Deliberately in `~/Documents` rather than
    /// Application Support: if the promise is "edit these outside the app", they have to
    /// be somewhere a person can reach without being told a trick.
    static var markdownRootURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return documents.appendingPathComponent(AppConstants.appName)
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.documentStorageMode)
        mode = DocumentStorageMode(rawValue: raw ?? "") ?? .encrypted
    }

    // MARK: - Switching

    enum SwitchError: LocalizedError {
        case exportFailed(count: Int, firstReason: String)

        var errorDescription: String? {
            switch self {
            case let .exportFailed(count, reason):
                "\(count) document(s) could not be written, so nothing was changed. First problem: \(reason)"
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
        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        try migrator.prepareRoot()

        let result = migrator.export(documents: documents.map(\.content), spaces: spaces)
        guard result.isSuccess else {
            throw SwitchError.exportFailed(
                count: result.failures.count,
                firstReason: result.failures.values.first ?? "unknown"
            )
        }

        // Derived state moves to the sidecar so it survives the switch.
        for document in documents where !document.derived.isEmpty {
            saveDerived(document.derived)
        }

        mode = .markdown
        logger.info("Switched document storage to plain markdown")
    }

    /// Switches back to encrypted storage, reading the folder first.
    ///
    /// The folder is **left in place** rather than deleted: those files are the user's,
    /// and deleting a folder in `~/Documents` on their behalf is not ours to do.
    func switchToEncrypted(knownSpaces: [Space]) -> [WritingDocument] {
        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        let imported = migrator.importAll(knownSpaces: knownSpaces)

        let documents = imported.documents.map { content in
            WritingDocument(content: content, derived: loadDerived(id: content.id))
        }

        if !imported.unidentifiedFiles.isEmpty {
            logger.info(
                "\(imported.unidentifiedFiles.count, privacy: .public) file(s) had no identifier and were left alone"
            )
        }

        mode = .encrypted
        logger.info("Switched document storage back to encrypted")
        return documents
    }

    // MARK: - Reading

    /// Loads all documents for the current mode.
    func loadDocuments(knownSpaces: [Space]) -> [WritingDocument]? {
        guard mode.isMarkdown else { return nil }

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        return migrator.importAll(knownSpaces: knownSpaces).documents.map { content in
            WritingDocument(content: content, derived: loadDerived(id: content.id))
        }
    }

    // MARK: - Writing

    /// Writes one document in the current mode. Returns whether it handled the write.
    @discardableResult
    func save(_ document: WritingDocument, spaces: [Space]) -> Bool {
        guard mode.isMarkdown else { return false }

        // Trash lives in the app, so a trashed document is removed from the folder
        // rather than written to it.
        if document.isTrashed {
            removeFile(for: document.id)
            saveDerived(document.derived)
            return true
        }

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        let result = migrator.export(documents: [document.content], spaces: spaces)
        if !result.isSuccess {
            logger.error("Could not write a document to the markdown folder")
        }
        saveDerived(document.derived)
        return true
    }

    /// Removes a document's file, used when it is trashed or deleted.
    func removeFile(for id: UUID) {
        guard mode.isMarkdown else { return }

        let migrator = MarkdownStorageMigrator(rootURL: Self.markdownRootURL)
        for url in migrator.markdownFiles() {
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  MarkdownDocumentFile.identifier(in: contents) == id
            else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Could not remove a document file: \(error.localizedDescription, privacy: .public)")
            }
            return
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
            try? FileManager.default.removeItem(at: url)
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
