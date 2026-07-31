import Foundation

// MARK: - Item

/// One row in the quick-open palette.
struct QuickOpenItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case document
        case meeting
    }

    let id: UUID
    let title: String
    let kind: Kind
}

// MARK: - Candidates

extension QuickOpenItem {
    /// Everything quick-open can jump to, most recently modified first.
    ///
    /// A function over plain arrays rather than something reading the stores, so the three rules
    /// that matter here are testable without a `@MainActor` store: trashed items are excluded,
    /// an untitled item still gets a name to match against, and the order is recency. That last
    /// one is not cosmetic — `QuickOpenMatcher` is stable within a rank, so the order it is
    /// handed is exactly what breaks ties between equally good matches.
    static func candidates(documents: [WritingDocument], meetings: [MeetingNote]) -> [QuickOpenItem] {
        let documentEntries = documents.lazy.filter { !$0.isTrashed }.map {
            (modifiedAt: $0.modifiedAt, item: QuickOpenItem(
                id: $0.id,
                title: $0.title.isEmpty ? AppConstants.defaultDocumentTitle : $0.title,
                kind: .document
            ))
        }
        let meetingEntries = meetings.lazy.filter { !$0.isTrashed }.map {
            (modifiedAt: $0.modifiedAt, item: QuickOpenItem(
                id: $0.id,
                title: $0.title.isEmpty ? AppConstants.defaultMeetingTitle : $0.title,
                kind: .meeting
            ))
        }
        return (Array(documentEntries) + Array(meetingEntries))
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map(\.item)
    }
}

// MARK: - Matcher

/// Ranks quick-open candidates by title.
///
/// Ranking is deliberately simple and local — exact, then prefix, then substring,
/// then initials-style subsequence — so the palette stays instant on large
/// libraries without touching the FTS index or the embedding store.
enum QuickOpenMatcher {
    /// Upper bound on returned rows, so a broad query cannot stall the palette.
    static let maxResults = 50

    static func match(query: String, in items: [QuickOpenItem]) -> [QuickOpenItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Array(items.prefix(maxResults)) }

        let scored: [(item: QuickOpenItem, rank: Int)] = items.compactMap { item in
            guard let rank = rank(of: item.title.lowercased(), for: trimmed) else { return nil }
            return (item, rank)
        }

        // Stable within a rank: preserve the caller's ordering (recency).
        let ordered = scored.enumerated().sorted { lhs, rhs in
            lhs.element.rank == rhs.element.rank
                ? lhs.offset < rhs.offset
                : lhs.element.rank < rhs.element.rank
        }
        return ordered.prefix(maxResults).map(\.element.item)
    }

    /// Lower is better; `nil` means no match.
    private static func rank(of title: String, for query: String) -> Int? {
        if title == query {
            return 0
        }
        if title.hasPrefix(query) {
            return 1
        }
        if title.contains(query) {
            return 2
        }
        if isSubsequence(query, of: title) {
            return 3
        }
        return nil
    }

    /// Whether `query`'s characters appear in `title` in order, allowing gaps —
    /// this is what makes "prm" find "Product Roadmap".
    private static func isSubsequence(_ query: String, of title: String) -> Bool {
        var remaining = Substring(title)
        for character in query {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}
