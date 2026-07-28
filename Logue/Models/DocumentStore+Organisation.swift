import Foundation
import OSLog

// MARK: - Saved Views & Document Types

/// Persistence and mutation for saved views and document types.
///
/// Both are small, whole-collection artifacts rather than per-item files, so each
/// is stored as a single encrypted file alongside the documents. They follow the
/// same encryption path as document content — these carry user-authored names and
/// filter values, so they are not less sensitive than the documents themselves.
extension DocumentStore {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentOrganisation")

    private var organisationDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/organisation")
    }

    private var savedViewsURL: URL {
        organisationDirectory.appendingPathComponent("saved-views.json")
    }

    private var documentTypesURL: URL {
        organisationDirectory.appendingPathComponent("document-types.json")
    }

    // MARK: - Loading

    /// Loads saved views and types. Safe to call more than once.
    func loadOrganisation() {
        savedViews = load([SavedView].self, from: savedViewsURL) ?? []
        documentTypes = load([DocumentType].self, from: documentTypesURL) ?? DocumentType.starterTypes
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try EncryptionManager.decryptCodable(type, from: data)
        } catch {
            Self.logger.error(
                "Failed to load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func persist(_ value: some Encodable, to url: URL) {
        let dir = organisationDirectory
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try EncryptionManager.encryptCodable(value)
                try data.write(to: url, options: .atomic)
            } catch {
                Self.logger.error(
                    "Failed to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Saved views

    func addSavedView(_ view: SavedView) {
        savedViews.append(view)
        persist(savedViews, to: savedViewsURL)
    }

    func updateSavedView(_ view: SavedView) {
        guard let index = savedViews.firstIndex(where: { $0.id == view.id }) else { return }
        savedViews[index] = view
        persist(savedViews, to: savedViewsURL)
    }

    func deleteSavedView(id: UUID) {
        savedViews.removeAll { $0.id == id }
        persist(savedViews, to: savedViewsURL)
    }

    /// Documents matching a saved view, or all active documents when the view is gone.
    func documents(matching viewID: UUID) -> [WritingDocument] {
        guard let view = savedViews.first(where: { $0.id == viewID }) else { return activeDocuments }
        return view.apply(to: documents)
    }

    // MARK: - Document types

    func addDocumentType(_ type: DocumentType) {
        documentTypes.append(type)
        persist(documentTypes, to: documentTypesURL)
    }

    func updateDocumentType(_ type: DocumentType) {
        guard let index = documentTypes.firstIndex(where: { $0.id == type.id }) else { return }
        documentTypes[index] = type
        persist(documentTypes, to: documentTypesURL)
    }

    /// Removes a type definition. Documents keep their `type` property — deleting a
    /// definition should not silently rewrite documents that use it.
    func deleteDocumentType(id: UUID) {
        documentTypes.removeAll { $0.id == id }
        persist(documentTypes, to: documentTypesURL)
    }

    /// Applies a type to a document and saves it.
    func applyType(_ type: DocumentType, to documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index] = type.applied(to: documents[index])
        documents[index].modifiedAt = Date()
        saveDocument(id: documentID)
    }

    // MARK: - Inbox

    var inboxDocuments: [WritingDocument] {
        InboxFilter.inbox(from: documents)
    }

    var inboxCount: Int {
        InboxFilter.count(in: documents)
    }

    /// Marks a document organised, returning the next inbox item for auto-advance.
    @discardableResult
    func markOrganised(id: UUID) -> WritingDocument? {
        guard let index = documentIndex(for: id) else { return nil }
        let next = InboxFilter.nextItem(after: id, in: documents)
        documents[index].isOrganised = true
        saveDocument(id: id)
        return next
    }

    // MARK: - Import

    /// Inserts a fully-formed document, as when importing a markdown file found on
    /// disk.
    ///
    /// Unlike `createDocument` this keeps the title and fields exactly as given, and
    /// does not select the result — an import should not steal the user's place.
    func insertDocument(_ document: WritingDocument) {
        guard documentIndex(for: document.id) == nil else { return }
        documents.insert(document, at: 0)
        rebuildIndexMap()
        saveDocument(id: document.id)
    }

    // MARK: - Changes made outside the app

    /// Applies what a scan of the markdown folder found.
    ///
    /// **Nothing is written back.** In markdown mode the file is the document, so the file is
    /// already correct by definition — and a write here would produce an event, which would
    /// produce a scan, which would produce a write. The one exception is trashing, because a
    /// trashed document has no file and has to be kept somewhere.
    func applyExternalChanges(_ plan: ExternalChangePlan) {
        guard !plan.isEmpty else { return }

        for content in plan.updated {
            guard let index = documentIndex(for: content.id) else { continue }
            // Derived state is kept: the AI caches belong to the document, not to the file,
            // and an edit outside the app does not invalidate them any more than one inside it.
            documents[index] = WritingDocument(content: content, derived: documents[index].derived)
        }

        for content in plan.inserted where documentIndex(for: content.id) == nil {
            // Inserted at the front to match `createDocument`, so a note dropped into the
            // folder shows up where a new note would.
            documents.insert(WritingDocument(content: content, derived: nil), at: 0)
        }

        rebuildIndexMap()

        // A file the user deleted outside the app goes to trash rather than vanishing:
        // deleting a file is easy to do by accident, and Logue's own trash is the one place
        // they can get it back from.
        for id in plan.trashed {
            deleteDocument(id: id)
        }

        invalidateCaches()
    }

    /// Replaces the whole document set, used after a storage-mode switch.
    ///
    /// Writes each document so the new backing store holds them all, rather than
    /// assuming the previous mode's files are still authoritative.
    func replaceAll(with documents: [WritingDocument]) {
        self.documents = documents
        rebuildIndexMap()
        for document in documents {
            saveDocument(id: document.id)
        }
        pruneStoredDocuments(keeping: Set(documents.map(\.id)))
    }

    /// Takes on the documents read back from the markdown folder when markdown storage is
    /// turned off.
    ///
    /// Trash lives in the app rather than in the folder — a deleted document should not sit
    /// in `~/Logue` waiting to be noticed — so trashed documents have no file to import.
    /// They are carried over from the encrypted copies that were never deleted, which is
    /// also why `replaceAll` can prune safely afterwards: by then they are in `documents`.
    func adoptAfterStorageSwitch(_ imported: [WritingDocument]) async {
        var restored = imported

        do {
            let stored = try await Self.readEncryptedDocuments(in: encryptedDocumentsDirectory)
            restored = Self.merging(imported: imported, carryingTrashFrom: stored)
        } catch {
            // The folder's documents are the ones that matter; losing the trash view is a
            // degraded result, not a failed switch.
            Self.logger.error(
                "Could not read trashed documents during storage switch: \(error.localizedDescription, privacy: .public)"
            )
        }

        replaceAll(with: restored)
    }

    /// The rule for combining folder documents with the encrypted trash.
    ///
    /// Pure and separate from the I/O so it can be tested: getting it wrong either loses
    /// the trash or resurrects a document the folder no longer has. Imported documents win
    /// on collision — the folder is the truth for anything that has a file.
    nonisolated static func merging(
        imported: [WritingDocument],
        carryingTrashFrom stored: [WritingDocument]
    ) -> [WritingDocument] {
        let importedIDs = Set(imported.map(\.id))
        return imported + stored.filter { $0.isTrashed && !importedIDs.contains($0.id) }
    }

    // MARK: - Bulk actions

    /// Applies a bulk transform to the selected documents and saves each changed one.
    func applyBulk(
        to ids: Set<UUID>,
        transform: ([WritingDocument]) -> [WritingDocument]
    ) {
        let selected = documents.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }

        // Every transformed document is saved. `WritingDocument` is not Equatable, so
        // there is no cheap unchanged check — and a bulk action is an explicit
        // operation on an explicit selection, so re-saving the selection is fine.
        for updated in transform(selected) {
            guard let index = documentIndex(for: updated.id) else { continue }
            documents[index] = updated
            saveDocument(id: updated.id)
        }
    }
}

// MARK: - Starter Types

extension DocumentType {
    /// Types offered on first run, so the feature is discoverable without asking the
    /// user to invent a taxonomy before they have written anything.
    static var starterTypes: [DocumentType] {
        [
            DocumentType(
                name: "Note", symbolName: "doc.text", colorName: "gray", sidebarOrder: 0
            ),
            DocumentType(
                name: "Project", symbolName: "briefcase", colorName: "blue", sidebarOrder: 10,
                pinnedProperties: ["status"],
                defaultProperties: ["status": .text("Active")],
                template: "## Goal\n\n## Next steps\n"
            ),
            DocumentType(
                name: "Person", symbolName: "person", colorName: "green", sidebarOrder: 20,
                pinnedProperties: ["author"]
            ),
            DocumentType(
                name: "Meeting Note", symbolName: "waveform", colorName: "purple", sidebarOrder: 30,
                template: "## Attendees\n\n## Decisions\n\n## Follow-ups\n"
            ),
        ]
    }
}
