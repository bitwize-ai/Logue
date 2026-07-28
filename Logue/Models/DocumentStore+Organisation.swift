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

        if let stored = load([DocumentType].self, from: documentTypesURL) {
            documentTypes = stored
        } else {
            // Persisted on first run rather than re-derived each launch. Left unsaved, the starter
            // types got fresh identifiers every time the app opened, so anything that referred to
            // one by id — a rename, a deletion — could not survive a restart.
            documentTypes = DocumentType.starterTypes
            persist(documentTypes, to: documentTypesURL)
        }
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

    /// Where saved views and types live, so a full erase reaches them.
    ///
    /// Extension-visible: DocumentStore
    var organisationStorageDirectory: URL {
        organisationDirectory
    }

    /// Restores saved views and types from a backup.
    ///
    /// `nil` means the backup predates them, so what is already loaded is kept rather than cleared —
    /// restoring an old backup should not silently delete views it never knew about.
    func replaceOrganisation(savedViews: [SavedView]?, documentTypes: [DocumentType]?) {
        if let savedViews {
            self.savedViews = savedViews
            persist(savedViews, to: savedViewsURL)
        }
        if let documentTypes {
            self.documentTypes = documentTypes
            persist(documentTypes, to: documentTypesURL)
        }
    }

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
            // Trashing loses the space, matching `deleteDocument`. Without this a bulk-trashed
            // document stayed filed in a space it is no longer part of.
            documents[index] = updated
            if updated.isTrashed {
                documents[index].spaceID = nil
                if documents[index].trashedAt == nil {
                    documents[index].trashedAt = Date()
                }
            }
            saveDocument(id: updated.id)
        }

        // Both of these are done by every single-document path and were missing here. The tag index
        // is memoised, so a bulk tag did not appear in the tag UI until some unrelated edit cleared
        // it — and, worse, bulk-trashing the open document left `selectedDocumentID` pointing at it,
        // so the editor went on displaying *and saving into* a document in the trash.
        if let selected = selectedDocumentID,
           documents.first(where: { $0.id == selected })?.isTrashed == true
        {
            selectedDocumentID = nil
        }
        invalidateCaches()
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
