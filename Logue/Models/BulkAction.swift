import Foundation

/// Pure transforms over a selection of documents.
///
/// Each returns updated copies rather than mutating a store, so the operations are
/// testable in isolation and the caller decides when to persist.
enum BulkAction {
    // MARK: - Tags

    /// Adds `tag` where missing. Comparison is case-insensitive, so adding
    /// "Urgent" to a document tagged "urgent" is a no-op rather than a near-duplicate.
    static func addingTag(_ tag: String, to documents: [WritingDocument]) -> [WritingDocument] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return documents }

        return documents.map { document in
            guard !document.tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { return document }

            var updated = document
            updated.tags.append(trimmed)
            updated.modifiedAt = Date()
            return updated
        }
    }

    static func removingTag(_ tag: String, from documents: [WritingDocument]) -> [WritingDocument] {
        documents.map { document in
            var updated = document
            updated.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            if updated.tags != document.tags {
                updated.modifiedAt = Date()
            }
            return updated
        }
    }

    // MARK: - Trash

    static func trashing(_ documents: [WritingDocument]) -> [WritingDocument] {
        let now = Date()
        return documents.map { document in
            var updated = document
            updated.isTrashed = true
            updated.trashedAt = now
            return updated
        }
    }

    static func restoring(_ documents: [WritingDocument]) -> [WritingDocument] {
        documents.map { document in
            var updated = document
            updated.isTrashed = false
            updated.trashedAt = nil
            return updated
        }
    }

    // MARK: - Spaces

    /// Files documents into a space, or unfiles them when `spaceID` is nil.
    static func moving(_ documents: [WritingDocument], toSpace spaceID: UUID?) -> [WritingDocument] {
        documents.map { document in
            var updated = document
            updated.spaceID = spaceID
            updated.modifiedAt = Date()
            return updated
        }
    }

    // MARK: - Inbox

    static func markingOrganised(_ documents: [WritingDocument]) -> [WritingDocument] {
        documents.map { document in
            var updated = document
            updated.isOrganised = true
            return updated
        }
    }
}

// MARK: - Inbox

/// The capture-then-organise inbox.
///
/// Fast capture should not require deciding where something belongs, so new
/// documents start unorganised and the inbox is the queue of things to file.
enum InboxFilter {
    /// Unorganised, untrashed documents, oldest first so the queue is processed in
    /// the order things were captured.
    static func inbox(from documents: [WritingDocument]) -> [WritingDocument] {
        documents
            .filter { !$0.isTrashed && !$0.isOrganised }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func count(in documents: [WritingDocument]) -> Int {
        inbox(from: documents).count
    }

    /// The item to open after `id` is organised, for auto-advance. Returns `nil`
    /// when nothing else is waiting.
    static func nextItem(after id: UUID, in documents: [WritingDocument]) -> WritingDocument? {
        let queue = inbox(from: documents)
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return queue.first }

        let remaining = queue.enumerated()
            .filter { $0.offset != index }
            .map(\.element)

        // Prefer the next item after the current one, wrapping to the first.
        if index < remaining.count {
            return remaining[index]
        }
        return remaining.first
    }
}
