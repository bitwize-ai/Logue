import Foundation

/// One title offered while completing a `[[` link.
struct WikiLinkCandidate: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let kind: LinkIndex.Kind
}

/// Filters and ranks link targets for the completion menu.
///
/// Ranking is delegated to `QuickOpenMatcher`, so the `[[` menu and the quick-open
/// palette order results the same way — one behaviour to learn, one to maintain.
enum WikiLinkCandidates {
    /// Upper bound on menu entries, so an empty query cannot build a menu of
    /// thousands of items.
    static let maxResults = 30

    static func matching(
        query: String,
        documents: [WritingDocument],
        meetings: [MeetingNote],
        excluding excludedID: UUID?
    ) -> [WikiLinkCandidate] {
        var items: [QuickOpenItem] = []
        var kinds: [UUID: LinkIndex.Kind] = [:]

        for document in documents where !document.isTrashed {
            guard document.id != excludedID,
                  !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            items.append(QuickOpenItem(id: document.id, title: document.title, kind: .document))
            kinds[document.id] = .document
        }

        for meeting in meetings {
            guard meeting.id != excludedID,
                  !meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            items.append(QuickOpenItem(id: meeting.id, title: meeting.title, kind: .meeting))
            kinds[meeting.id] = .meeting
        }

        return QuickOpenMatcher.match(query: query, in: items)
            .prefix(maxResults)
            .compactMap { item in
                guard let kind = kinds[item.id] else { return nil }
                return WikiLinkCandidate(id: item.id, title: item.title, kind: kind)
            }
    }
}
