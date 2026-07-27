import Foundation
import os.log

/// Appends " (2)", " (3)" etc. if `proposed` already exists in `existingTitles`.
func uniqueTitle(_ proposed: String, among existingTitles: [String]) -> String {
    guard existingTitles.contains(proposed) else { return proposed }
    var counter = 2
    while counter < 10000, existingTitles.contains("\(proposed) (\(counter))") {
        counter += 1
    }
    return "\(proposed) (\(counter))"
}

/// Central observable document library. Persists to Application Support as JSON.
@Observable
@MainActor
final class DocumentStore {
    static let shared = DocumentStore()
    private init() {
        Task { await loadFromDiskAsync() }
        loadOrganisation()
    }

    // Extension-visible: +AITitle
    let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")

    // MARK: - State

    // B7: Removed didSet index rebuild — call rebuildIndexMap() explicitly after bulk operations
    var documents: [WritingDocument] = []
    // Extension-visible: +Organisation
    /// Saved filters shown in the sidebar.
    var savedViews: [SavedView] = []
    // Extension-visible: +Organisation
    /// Type definitions available to documents.
    var documentTypes: [DocumentType] = []

    var selectedDocumentID: UUID?

    /// True once `loadFromDiskAsync()` has finished.
    private(set) var isLoaded = false
    /// True only when seed/sample data was actually loaded (not real user data from disk).
    var loadedSeedData = false

    /// Serialized save task — cancels previous in-flight write so the latest snapshot always wins.
    @ObservationIgnored private var _saveTask: Task<Void, Never>?

    /// O(1) UUID → array index lookup cache. Rebuilt whenever `documents` changes.
    @ObservationIgnored private var _documentIndexMap: [UUID: Int] = [:]

    func rebuildIndexMap() {
        var map = [UUID: Int](minimumCapacity: documents.count)
        for (i, doc) in documents.enumerated() {
            map[doc.id] = i
        }
        _documentIndexMap = map
    }

    // Extension-visible: +Organisation
    /// Returns the array index for a document by UUID in O(1).
    func documentIndex(for id: UUID) -> Int? {
        if let idx = _documentIndexMap[id], idx < documents.count, documents[idx].id == id {
            return idx
        }
        // Fallback linear search if map is stale
        return documents.firstIndex { $0.id == id }
    }

    var selectedDocument: WritingDocument? {
        guard let id = selectedDocumentID else { return nil }
        guard let idx = documentIndex(for: id) else { return nil }
        return documents[idx]
    }

    // MARK: - Computed Subsets

    var activeDocuments: [WritingDocument] {
        documents.filter { !$0.isTrashed }
    }

    var recentDocuments: [WritingDocument] {
        activeDocuments.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(10).map { $0 }
    }

    var pinnedDocuments: [WritingDocument] {
        activeDocuments.filter(\.isPinned)
    }

    var trashedDocuments: [WritingDocument] {
        documents.filter(\.isTrashed)
    }

    // MARK: - CRUD

    @discardableResult
    func createDocument(
        title: String = "Untitled Document",
        body: String = "",
        inSpace spaceID: UUID? = nil,
        select: Bool = true
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = uniqueTitle(title, among: activeDocuments.map(\.title))
        doc.body = body
        doc.spaceID = spaceID
        documents.insert(doc, at: 0)
        rebuildIndexMap()
        if select {
            selectedDocumentID = doc.id
        }
        saveDocument(id: doc.id)
        return doc
    }

    func updateDocument(_ document: WritingDocument) {
        guard let index = documentIndex(for: document.id) else { return }
        var updated = document
        updated.modifiedAt = Date()
        documents[index] = updated
        saveDocument(id: document.id)
    }

    /// Update only the chat messages for a document (avoids overwriting other fields).
    func setChatMessages(_ messages: [ChatMessage], for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].chatMessages = messages
        saveDocument(id: documentID)
    }

    // MARK: - AI Panel Result Setters

    func setReviewGrade(_ grade: OverallGrade?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].reviewGrade = grade
        saveDocument(id: documentID)
    }

    func setReviewReactions(_ reactions: [SectionReaction]?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].reviewReactions = reactions
        saveDocument(id: documentID)
    }

    func setFactChecks(_ checks: [FactCheck]?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].factChecks = checks
        saveDocument(id: documentID)
    }

    func setPIIFindings(_ findings: [PIIFinding]?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].piiFindings = findings
        saveDocument(id: documentID)
    }

    func setVocabSuggestions(_ suggestions: [VocabSuggestion]?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].vocabSuggestions = suggestions
        saveDocument(id: documentID)
    }

    func setAIDetectionResult(_ result: String?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].aiDetectionResult = result
        saveDocument(id: documentID)
    }

    func setPlagiarismResult(_ result: String?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].plagiarismResult = result
        saveDocument(id: documentID)
    }

    func setRewriteResult(_ result: RewriteResult?, for documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].rewriteResult = result
        saveDocument(id: documentID)
    }

    func deleteDocument(id: UUID) {
        guard let index = documentIndex(for: id) else { return }
        documents[index].isTrashed = true
        documents[index].trashedAt = Date()
        documents[index].spaceID = nil
        if selectedDocumentID == id {
            selectedDocumentID = nil
        }
        invalidateCaches()
        saveDocument(id: id)
    }

    func restoreDocument(id: UUID) {
        guard let index = documentIndex(for: id) else { return }
        documents[index].isTrashed = false
        documents[index].trashedAt = nil
        invalidateCaches()
        saveDocument(id: id)
    }

    func permanentlyDeleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        rebuildIndexMap()
        if selectedDocumentID == id {
            selectedDocumentID = nil
        }
        // Both stores: a trashed document lives in encrypted storage even in markdown mode,
        // and one deleted without being trashed first still has its file.
        DocumentStorage.shared.removeFile(for: id)
        deleteDocumentFile(id: id)
    }

    func trashDocuments(inSpace spaceID: UUID) {
        var affectedIDs: [UUID] = []
        for index in documents.indices where documents[index].spaceID == spaceID && !documents[index].isTrashed {
            documents[index].isTrashed = true
            documents[index].trashedAt = Date()
            documents[index].spaceID = nil
            affectedIDs.append(documents[index].id)
        }
        if let sel = selectedDocumentID, documentIndex(for: sel).map({ documents[$0].isTrashed }) == true {
            selectedDocumentID = nil
        }
        invalidateCaches()
        for id in affectedIDs {
            saveDocument(id: id)
        }
    }

    func emptyDocumentTrash() {
        let trashedIDs = documents.filter(\.isTrashed).map(\.id)
        documents.removeAll(where: \.isTrashed)
        rebuildIndexMap()
        for id in trashedIDs {
            deleteDocumentFile(id: id)
        }
    }

    func renameDocument(id: UUID, newTitle: String) {
        guard let index = documentIndex(for: id) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let otherTitles = activeDocuments.filter { $0.id != id }.map(\.title)
        let oldTitle = documents[index].title
        let resolved = uniqueTitle(trimmed, among: otherTitles)
        documents[index].title = resolved
        documents[index].modifiedAt = Date()
        saveDocument(id: id)

        repairInboundLinks(from: oldTitle, to: resolved, renamedID: id)
    }

    /// Retargets `[[wikilinks]]` and relationship fields that pointed at the old
    /// title, so a rename does not silently break every inbound reference.
    ///
    /// Each affected document is saved individually. A failure part-way through
    /// therefore leaves earlier documents repaired and later ones stale rather than
    /// rolling back — the encrypted store has no cross-document transaction. Stale
    /// links show up as "Unresolved" in the Links panel rather than being lost, so
    /// partial repair degrades visibly instead of silently.
    private func repairInboundLinks(from oldTitle: String, to newTitle: String, renamedID: UUID) {
        guard oldTitle.caseInsensitiveCompare(newTitle) != .orderedSame else { return }

        for document in documents where document.id != renamedID {
            guard !document.isTrashed,
                  LinkRenamer.needsRewrite(document: document, from: oldTitle),
                  let index = documentIndex(for: document.id)
            else { continue }

            let updated = LinkRenamer.rewriting(document: document, from: oldTitle, to: newTitle)
            guard updated.body != document.body
                || updated.relationships != document.relationships
            else { continue }

            documents[index] = updated
            documents[index].modifiedAt = Date()
            saveDocument(id: document.id)
        }
    }

    func togglePin(id: UUID) {
        guard let index = documentIndex(for: id) else { return }
        documents[index].isPinned.toggle()
        saveDocument(id: id)
    }

    // MARK: - Tags

    func addTag(_ tag: String, to documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !documents[index].tags.contains(trimmed) else { return }
        documents[index].tags.append(trimmed)
        documents[index].modifiedAt = Date()
        _cachedAllTags = nil
        saveDocument(id: documentID)
    }

    func removeTag(_ tag: String, from documentID: UUID) {
        guard let index = documentIndex(for: documentID) else { return }
        documents[index].tags.removeAll { $0 == tag }
        documents[index].modifiedAt = Date()
        _cachedAllTags = nil
        saveDocument(id: documentID)
    }

    @ObservationIgnored private var _cachedAllTags: [String]?

    /// Arch-6: Invalidate cached computed subsets after bulk operations (e.g., backup import).
    func invalidateCaches() {
        _cachedAllTags = nil
    }

    var allTags: [String] {
        if let cached = _cachedAllTags {
            return cached
        }
        let result = Array(Set(documents.flatMap(\.tags))).sorted()
        _cachedAllTags = result
        return result
    }

    // MARK: - Space Operations

    func documents(inSpace spaceID: UUID) -> [WritingDocument] {
        documents.filter { $0.spaceID == spaceID && !$0.isTrashed }
    }

    func moveDocument(id: UUID, toSpace spaceID: UUID?) {
        guard let index = documentIndex(for: id) else { return }
        documents[index].spaceID = spaceID
        documents[index].modifiedAt = Date()
        saveDocument(id: id)
    }

    /// Unfile all documents in a space (used before space deletion).
    func unfileDocuments(inSpace spaceID: UUID) {
        var affectedIDs: [UUID] = []
        for index in documents.indices where documents[index].spaceID == spaceID {
            documents[index].spaceID = nil
            affectedIDs.append(documents[index].id)
        }
        for id in affectedIDs {
            saveDocument(id: id)
        }
    }

    // MARK: - Persistence (per-document file storage)

    private var documentsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/documents")
    }

    private func fileURL(for id: UUID) -> URL {
        documentsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Per-document save tasks — cancels previous write for the same document so latest snapshot wins.
    @ObservationIgnored private var _documentSaveTasks: [UUID: Task<Void, Never>] = [:]

    /// Saves a single document to its own file.
    func saveDocument(id: UUID) {
        guard let index = documentIndex(for: id) else { return }
        let doc = documents[index]

        // Checked before the encrypted write, not after: in markdown mode the file *is*
        // the document, and writing both would recreate the two-copies problem this
        // storage design exists to avoid.
        if DocumentStorage.shared.save(doc, spaces: SpaceStore.shared.spaces) {
            Task.detached(priority: .utility) { await SemanticIndex.shared.indexDocument(doc) }
            return
        }

        let url = fileURL(for: id)
        let dir = documentsDirectory
        _documentSaveTasks[id]?.cancel()
        _documentSaveTasks[id] = Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard !Task.isCancelled else { return }
                let data = try EncryptionManager.encryptCodable(doc)
                guard !Task.isCancelled else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                    .error("Failed to save document \(id): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Best-effort semantic re-index — hash-checked, so unchanged bodies are skipped.
        Task.detached(priority: .utility) {
            await SemanticIndex.shared.indexDocument(doc)
        }
    }

    /// Saves ALL documents — each to its own file. Cancels any previous bulk save in flight.
    func saveToDisk() {
        _saveTask?.cancel()
        let snapshot = documents
        let dir = documentsDirectory
        _saveTask = Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for doc in snapshot {
                    guard !Task.isCancelled else { return }
                    let url = dir.appendingPathComponent("\(doc.id.uuidString).json")
                    let data = try EncryptionManager.encryptCodable(doc)
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                guard !Task.isCancelled else { return }
                Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                    .error("Failed to save documents: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes encrypted files for documents that no longer exist.
    ///
    /// Switching to plain markdown deliberately leaves the encrypted originals alone, so
    /// a bad export is never destructive. The cost is that a document deleted while
    /// markdown storage was on still has its old encrypted file — and encrypted loading
    /// reads the whole directory, so it would come back on the next launch. Pruning on
    /// the way back closes that without ever deleting at the risky moment.
    ///
    /// Extension-visible: +Organisation
    func pruneStoredDocuments(keeping ids: Set<UUID>) {
        // While markdown storage is on, the encrypted files are the untouched pre-switch
        // copies, not a stale view of the truth. Pruning them then would throw away the
        // very fallback that makes enabling markdown storage safe.
        guard !DocumentStorage.shared.mode.isMarkdown else { return }

        let dir = documentsDirectory
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: dir.path) else { return }
            do {
                let files = try fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                )
                for file in Self.staleDocumentFiles(among: files, keeping: ids) {
                    try fm.removeItem(at: file)
                }
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                    .error("Could not prune stored documents: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Which files in the encrypted directory belong to no live document.
    ///
    /// Pure and separate from the deletion so it can be tested — this decides what gets
    /// removed, so anything it wrongly includes is lost data. Only `.json` files whose name
    /// is a UUID qualify: an unrecognised file is left alone rather than assumed to be ours.
    ///
    /// Extension-visible: +Organisation
    nonisolated static func staleDocumentFiles(among files: [URL], keeping ids: Set<UUID>) -> [URL] {
        files.filter { file in
            guard file.pathExtension == "json",
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            else { return false }
            return !ids.contains(id)
        }
    }

    /// Deletes the individual file for a permanently-deleted document.
    private func deleteDocumentFile(id: UUID) {
        let url = fileURL(for: id)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
            await SemanticIndex.shared.removeDocument(id: id)
        }
    }

    func clearAllData() {
        documents = []
        selectedDocumentID = nil
        let dir = documentsDirectory
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: dir)
            // Note: SemanticIndex spans both meetings and documents — clearing only the
            // document namespace via `removeDocument` would be inefficient. We rely on
            // `MeetingStore.clearAllData()` (which calls `SemanticIndex.clearAll()`)
            // to nuke both namespaces during full app reset.
        }
    }

    /// Reads every encrypted document file in a directory, off the main thread.
    ///
    /// A file that cannot be decrypted or decoded is skipped and logged rather than
    /// failing the whole read — one corrupt document should not hide the rest.
    ///
    /// Extension-visible: +Organisation
    nonisolated static func readEncryptedDocuments(in directory: URL) async throws -> [WritingDocument] {
        try await Task.detached {
            let fm = FileManager.default
            let files = try fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )
            var docs: [WritingDocument] = []
            for file in files where file.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: file)
                    try docs.append(
                        EncryptionManager.decryptCodableWithFallback(WritingDocument.self, from: data)
                    )
                } catch {
                    Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                        .error("Skipping corrupt document file \(file.lastPathComponent): \(error.localizedDescription, privacy: .public)")
                }
            }
            return docs
        }.value
    }

    /// The encrypted document directory, so a storage switch can read what is still there.
    ///
    /// Extension-visible: +Organisation
    var encryptedDocumentsDirectory: URL {
        documentsDirectory
    }

    private func loadFromDiskAsync() async {
        // Markdown mode reads the folder instead; the encrypted files are not the truth
        // while it is on, apart from the trash, which has no file by design.
        if let fromMarkdown = await DocumentStorage.shared.loadDocuments(
            knownSpaces: SpaceStore.shared.spaces, trashedFrom: documentsDirectory
        ) {
            documents = fromMarkdown
            rebuildIndexMap()
            isLoaded = true
            // Anything that changed while the app was not running is picked up here, before
            // the watcher takes over.
            DocumentStorage.shared.startWatchingIfNeeded()
            DocumentStorage.shared.rescan()
            return
        }

        let dir = documentsDirectory
        let hasClearedSeed = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hasClearedSeedData)

        let dirExists = FileManager.default.fileExists(atPath: dir.path)

        guard dirExists else {
            let useSeed = !hasClearedSeed
            documents = useSeed ? Self.makeSeedDocuments() : []
            loadedSeedData = useSeed
            rebuildIndexMap()
            saveToDisk()
            isLoaded = true
            return
        }

        do {
            let loaded = try await Self.readEncryptedDocuments(in: dir)

            guard !loaded.isEmpty else {
                documents = []
                rebuildIndexMap()
                selectedDocumentID = nil
                isLoaded = true
                return
            }
            documents = loaded
            rebuildIndexMap()
            // Build semantic embedding index after loading. Hash-checked per-document
            // so this is cheap once the index has been built once.
            let snapshot = documents
            Task.detached(priority: .utility) {
                for doc in snapshot {
                    await SemanticIndex.shared.indexDocument(doc)
                }
            }
            isLoaded = true
        } catch {
            logger.error("Failed to load documents from disk: \(error.localizedDescription, privacy: .public)")
            let useSeed = !hasClearedSeed
            documents = useSeed ? Self.makeSeedDocuments() : []
            loadedSeedData = useSeed
            rebuildIndexMap()
            saveToDisk()
            isLoaded = true
        }
    }
}
