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
    }

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")

    // MARK: - State

    // B7: Removed didSet index rebuild — call rebuildIndexMap() explicitly after bulk operations
    var documents: [WritingDocument] = []

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

    /// Returns the array index for a document by UUID in O(1).
    private func documentIndex(for id: UUID) -> Int? {
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
        documents[index].title = uniqueTitle(trimmed, among: otherTitles)
        documents[index].modifiedAt = Date()
        saveDocument(id: id)
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

    // MARK: - AI Title Generation (Local LLM)

    func generateAITitle(for documentID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("generateAITitle: no model loaded")
            return
        }
        guard let doc = documents.first(where: { $0.id == documentID }) else { return }

        let text = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 50 else { return }

        let prompt = """
        Generate a short title (3-7 words, title case) for this document. \
        Rules: Do NOT include author names or words like "Meeting", "Email", "Document". \
        The title should describe the topic as a noun phrase, not a sentence. \
        Output ONLY the title, nothing else.

        Document:
        \(String(text.prefix(2000)))

        Title:
        """

        if let cleanTitle = await generateTitle(prompt: prompt) {
            if let index = documentIndex(for: documentID),
               isDefaultDocumentTitle(documents[index].title)
            {
                documents[index].title = uniqueTitle(cleanTitle, among: activeDocuments.map(\.title))
                documents[index].modifiedAt = Date()
                saveDocument(id: documentID)
            }
        }
    }

    /// Re-generate a title, considering the current title and content changes.
    func regenerateAITitle(for documentID: UUID) async {
        guard await LLMEngine.shared.isModelLoaded else {
            logger.warning("regenerateAITitle: no model loaded")
            return
        }
        guard let doc = documents.first(where: { $0.id == documentID }) else { return }

        let text = doc.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 20 else { return }

        let currentTitle = doc.title

        let prompt = if isDefaultDocumentTitle(currentTitle) {
            """
            Generate a short title (3-7 words, title case) for this document. \
            Rules: Do NOT include author names or words like "Meeting", "Email", "Document". \
            The title should describe the topic as a noun phrase, not a sentence. \
            Output ONLY the title, nothing else.

            Document:
            \(String(text.prefix(2000)))

            Title:
            """
        } else {
            """
            The current title is: "\(currentTitle)"
            Below is the document content. If the topic still matches the current title, return the same title. \
            Only generate a new title (3-7 words, title case) if the topic has significantly changed. \
            Do NOT include author names or words like "Meeting", "Email", "Document". \
            Output ONLY the title, nothing else.

            Document:
            \(String(text.prefix(2000)))

            Title:
            """
        }

        if let cleanTitle = await generateTitle(prompt: prompt) {
            if let index = documentIndex(for: documentID) {
                documents[index].title = cleanTitle
                documents[index].modifiedAt = Date()
                saveDocument(id: documentID)
            }
        }
    }

    private func generateTitle(prompt: String) async -> String? {
        await AITitleGenerator.generate(prompt: prompt)
    }

    private func isDefaultDocumentTitle(_ title: String) -> Bool {
        title == "Untitled Document"
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

    private func loadFromDiskAsync() async {
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
            // Heavy I/O + decrypt + decode off main thread
            let loaded: [WritingDocument] = try await Task.detached {
                let fm = FileManager.default
                let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                var docs: [WritingDocument] = []
                for file in files where file.pathExtension == "json" {
                    do {
                        let data = try Data(contentsOf: file)
                        let doc = try EncryptionManager.decryptCodableWithFallback(WritingDocument.self, from: data)
                        docs.append(doc)
                    } catch {
                        Logger(subsystem: AppConstants.bundleID, category: "DocumentStore")
                            .error("Skipping corrupt document file \(file.lastPathComponent): \(error.localizedDescription, privacy: .public)")
                    }
                }
                return docs
            }.value

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
