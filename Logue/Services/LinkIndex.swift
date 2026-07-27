import Foundation

/// An immutable snapshot of the wikilink graph across documents and meetings.
///
/// Built from titles and bodies, so it stays independent of the stores and is
/// cheap to unit-test. Rebuild it when content changes rather than mutating it —
/// the graph is small enough (thousands of items) that a rebuild is far simpler
/// than incremental invalidation, and correctness matters more here than speed.
///
/// Generalises the existing meeting ↔ document link model to arbitrary titles.
struct LinkIndex: Sendable {
    // MARK: - Entry

    enum Kind: Equatable, Sendable {
        case document
        case meeting
    }

    /// One indexed item. `body` is scanned for `[[wikilinks]]`.
    struct Entry: Sendable {
        let id: UUID
        let title: String
        let body: String
        let kind: Kind
    }

    // MARK: - Storage

    private let titles: [UUID: String]
    private let kinds: [UUID: Kind]
    /// Lowercased, trimmed title → item ID. Titles are not unique in the app, so a
    /// collision keeps the first entry rather than trapping or dropping both.
    private let idsByNormalisedTitle: [String: UUID]
    private let outgoingByID: [UUID: [UUID]]
    private let backlinksByID: [UUID: [UUID]]
    private let brokenByID: [UUID: [String]]

    // MARK: - Build

    init(entries: [Entry]) {
        var titles: [UUID: String] = [:]
        var kinds: [UUID: Kind] = [:]
        var idsByTitle: [String: UUID] = [:]

        for entry in entries {
            titles[entry.id] = entry.title
            kinds[entry.id] = entry.kind
            let key = Self.normalise(entry.title)
            // First writer wins on a duplicate title — deterministic for a given input order.
            if !key.isEmpty, idsByTitle[key] == nil {
                idsByTitle[key] = entry.id
            }
        }

        var outgoing: [UUID: [UUID]] = [:]
        var backlinks: [UUID: [UUID]] = [:]
        var broken: [UUID: [String]] = [:]

        for entry in entries {
            var resolved: [UUID] = []
            var unresolved: [String] = []

            for target in WikiLinkParser.uniqueTargets(in: entry.body) {
                guard let targetID = idsByTitle[Self.normalise(target)] else {
                    unresolved.append(target)
                    continue
                }
                // A note linking to itself is not a graph edge.
                guard targetID != entry.id else { continue }
                resolved.append(targetID)
                backlinks[targetID, default: []].append(entry.id)
            }

            if !resolved.isEmpty {
                outgoing[entry.id] = resolved
            }
            if !unresolved.isEmpty {
                broken[entry.id] = unresolved
            }
        }

        self.titles = titles
        self.kinds = kinds
        idsByNormalisedTitle = idsByTitle
        outgoingByID = outgoing
        backlinksByID = backlinks
        brokenByID = broken
    }

    // MARK: - Queries

    /// Items that `id` links to, deduplicated, in first-mention order.
    func outgoing(from id: UUID) -> [UUID] {
        outgoingByID[id] ?? []
    }

    /// Items that link to `id`.
    func backlinks(to id: UUID) -> [UUID] {
        backlinksByID[id] ?? []
    }

    /// Link targets in `id`'s body that match no known title — the broken links.
    func brokenTargets(from id: UUID) -> [String] {
        brokenByID[id] ?? []
    }

    /// The item a link target refers to, if any.
    func resolve(target: String) -> UUID? {
        idsByNormalisedTitle[Self.normalise(target)]
    }

    func title(of id: UUID) -> String? {
        titles[id]
    }

    func kind(of id: UUID) -> Kind? {
        kinds[id]
    }

    /// Every item with at least one outgoing or incoming link.
    var linkedItemIDs: Set<UUID> {
        Set(outgoingByID.keys).union(backlinksByID.keys)
    }

    // MARK: - Private

    /// Titles are matched case-insensitively and ignore surrounding whitespace,
    /// so `[[  alpha ]]` finds a note titled `Alpha`.
    private static func normalise(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Building From Stores

extension LinkIndex {
    /// Builds the graph from store models.
    ///
    /// Trashed documents are excluded entirely — they are neither indexed items nor
    /// resolvable targets, so a link to one is reported as broken rather than
    /// silently resolving to something the user believes they deleted.
    static func build(documents: [WritingDocument], meetings: [MeetingNote]) -> LinkIndex {
        var entries: [Entry] = []

        for document in documents where !document.isTrashed {
            entries.append(Entry(
                id: document.id,
                title: document.title,
                body: document.body,
                kind: .document
            ))
        }

        for meeting in meetings {
            // The AI summary is the meeting's prose surface; raw transcript segments
            // are speech and would not contain hand-written wikilinks.
            entries.append(Entry(
                id: meeting.id,
                title: meeting.title,
                body: meeting.summary ?? "",
                kind: .meeting
            ))
        }

        return LinkIndex(entries: entries)
    }
}
