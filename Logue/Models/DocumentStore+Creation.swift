import Foundation

/// Making documents, one at a time or a batch at a time.
///
/// The batch path exists because an import is not a loop of single creations: done that way, each
/// document re-derives the set of existing titles, inserts at the front of the array and rebuilds
/// the whole index map, all of which are O(N) in the library.
@MainActor
extension DocumentStore {
    /// One document an import intends to create.
    struct DocumentDraft {
        let title: String
        let body: String
        let tags: [String]
        let createdAt: Date?
        let modifiedAt: Date?
        let properties: [String: PropertyValue]
    }

    /// `tags` are set before the first save rather than added afterwards: `addTag` saves
    /// each time, and in markdown mode a save walks the whole folder, so a tagged import
    /// paid that once per tag on top of once per document.
    @discardableResult
    func createDocument(
        title: String = "Untitled Document",
        body: String = "",
        tags: [String] = [],
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        properties: [String: PropertyValue] = [:],
        inSpace spaceID: UUID? = nil,
        select: Bool = true
    ) -> WritingDocument {
        let item = DocumentDraft(
            title: title, body: body, tags: tags,
            createdAt: createdAt, modifiedAt: modifiedAt, properties: properties
        )
        let doc = draft(
            item, titled: uniqueTitle(title, among: activeDocuments.map(\.title)), spaceID: spaceID
        )
        documents.insert(doc, at: 0)
        rebuildIndexMap()
        if select {
            selectedDocumentID = doc.id
        }
        saveDocument(id: doc.id)
        return doc
    }

    /// A document that has not been inserted yet. Shared so the batch path below cannot drift
    /// from the single-document one.
    private func draft(
        _ item: DocumentDraft, titled title: String, spaceID: UUID?
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.body = item.body
        doc.tags = item.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        doc.spaceID = spaceID
        // Stamped only when the app-wide default is not `normal`, because `widthMode` already
        // reads an absent value as `normal`. Writing it regardless would put a redundant
        // `width:` line in the frontmatter of every new file in markdown storage mode.
        let defaultWidth = DocumentWidthMode.appDefault
        if defaultWidth != .normal {
            doc.widthMode = defaultWidth
        }
        if !item.properties.isEmpty {
            doc.properties = item.properties
        }
        if let createdAt = item.createdAt {
            doc.createdAt = createdAt
            // A note older than today did not arrive edited. Leaving `modifiedAt` at `Date()`
            // would put every imported note at the top of "recently modified" forever.
            doc.modifiedAt = createdAt
        }
        // The file's own modified date wins over that fallback when it states one, so a note
        // written in 2019 and edited last week does not import as last modified in 2019.
        if let modifiedAt = item.modifiedAt {
            doc.modifiedAt = modifiedAt
        }
        return doc
    }

    /// Creates many documents in one pass, for imports.
    ///
    /// The point is the work that is *not* repeated. Done one at a time, each document rebuilds a
    /// fresh array of every existing title to uniquify against, inserts at the front, and rebuilds
    /// the whole index map — all O(N), so a 500-note import was quadratic three times over before
    /// it wrote a single file. Here the title set is carried across the batch and the index is
    /// rebuilt once.
    ///
    /// Saving still happens per document, because each one is a separate file. It yields between
    /// batches of them: each save is real file I/O on the main actor, so a flat 500-file import
    /// was one uninterrupted turn even after the O(N) work collapsed.
    @discardableResult
    func createDocuments(_ drafts: [DocumentDraft], inSpace spaceID: UUID?) async -> [UUID] {
        guard !drafts.isEmpty else { return [] }

        var taken = Set(activeDocuments.map(\.title))
        var created: [WritingDocument] = []
        created.reserveCapacity(drafts.count)

        for item in drafts {
            let title = uniqueTitle(item.title, among: taken)
            taken.insert(title)
            created.append(draft(item, titled: title, spaceID: spaceID))
        }

        documents.insert(contentsOf: created, at: 0)
        rebuildIndexMap()
        // Tags set in `draft` rather than through `addTag`, which is what stopped the per-tag save
        // — but `addTag` was also the only thing dropping the cached tag list. Without this, tags
        // imported from a vault are missing from the filter chips and from autocomplete until some
        // unrelated edit happens to invalidate it.
        invalidateCaches()

        // No cancellation check in here. Once these are in `documents`, every one of them has to
        // reach disk: stopping half way left the rest in memory with no file, and the caller would
        // still report the import as cancelled and nothing created. The yields keep the window
        // alive; the caller checks cancellation before it asks for the next batch.
        for (index, doc) in created.enumerated() {
            if index > 0, index.isMultiple(of: Self.savesPerYield) {
                await Task.yield()
            }
            saveDocument(id: doc.id)
        }
        return created.map(\.id)
    }

    /// How many documents are written between yields. Small enough that the window stays alive,
    /// large enough that the yields themselves are not the cost.
    private static let savesPerYield = 20
}
