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
        properties: [String: PropertyValue] = [:],
        inSpace spaceID: UUID? = nil,
        select: Bool = true
    ) -> WritingDocument {
        let doc = draft(
            title: uniqueTitle(title, among: activeDocuments.map(\.title)),
            body: body, tags: tags, createdAt: createdAt, properties: properties, spaceID: spaceID
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
        title: String,
        body: String,
        tags: [String],
        createdAt: Date?,
        properties: [String: PropertyValue],
        spaceID: UUID?
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        doc.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        doc.spaceID = spaceID
        if !properties.isEmpty {
            doc.properties = properties
        }
        if let createdAt {
            doc.createdAt = createdAt
            // A note older than today did not arrive edited. Leaving `modifiedAt` at `Date()`
            // would put every imported note at the top of "recently modified" forever.
            doc.modifiedAt = createdAt
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
    /// Saving still happens per document, because each one is a separate file.
    @discardableResult
    func createDocuments(_ drafts: [DocumentDraft], inSpace spaceID: UUID?) -> [UUID] {
        guard !drafts.isEmpty else { return [] }

        var taken = Set(activeDocuments.map(\.title))
        var created: [WritingDocument] = []
        created.reserveCapacity(drafts.count)

        for item in drafts {
            let title = uniqueTitle(item.title, among: taken)
            taken.insert(title)
            created.append(draft(
                title: title, body: item.body, tags: item.tags,
                createdAt: item.createdAt, properties: item.properties, spaceID: spaceID
            ))
        }

        documents.insert(contentsOf: created, at: 0)
        rebuildIndexMap()
        for doc in created {
            saveDocument(id: doc.id)
        }
        return created.map(\.id)
    }
}
