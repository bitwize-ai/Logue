import Foundation
import OSLog

// MARK: - Relative Dates

/// Resolves the date expressions a saved view can hold.
///
/// Views are meant to keep moving — "changed this week" should mean *this* week
/// every time it runs — so filters store an expression, not a fixed timestamp.
enum RelativeDate {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "RelativeDate")

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// Resolves `expression` against `now`. `now` is a parameter rather than
    /// `Date()` so filters are deterministic and testable.
    static func resolve(_ expression: String, now: Date) -> Date? {
        let key = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let calendar = Calendar.current

        switch key {
        case "today":
            return calendar.startOfDay(for: now)
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case "one week ago", "1 week ago":
            return calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))
        case "one month ago", "1 month ago":
            return calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))
        case "one year ago", "1 year ago":
            return calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now))
        default:
            return isoFormatter.date(from: key)
        }
    }
}

// MARK: - Field

/// What a condition looks at.
enum FilterField: Equatable, Codable, Sendable {
    case title
    case body
    case tag
    case modifiedAt
    case createdAt
    case property(String)
    /// Whether the document is pinned. Added so the sidebar's built-in filters are expressible as
    /// a saved view — without it, "save what I am looking at" could not capture Pinned or Inbox.
    case isPinned
    /// Whether the document has been triaged out of the Inbox.
    case isOrganised

    var label: String {
        switch self {
        case .title: "Title"
        case .body: "Body"
        case .tag: "Tag"
        case .modifiedAt: "Modified"
        case .createdAt: "Created"
        case .isPinned: "Pinned"
        case .isOrganised: "Organised"
        case let .property(key): key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isDate: Bool {
        self == .modifiedAt || self == .createdAt
    }
}

// MARK: - Comparator

enum FilterComparator: String, Equatable, Codable, CaseIterable, Sendable {
    case `is`
    case isNot
    case contains
    case doesNotContain
    case isEmpty
    case isNotEmpty
    case matchesRegex
    case isOnOrAfter
    case isBefore

    var label: String {
        switch self {
        case .is: "is"
        case .isNot: "is not"
        case .contains: "contains"
        case .doesNotContain: "does not contain"
        case .isEmpty: "is empty"
        case .isNotEmpty: "is not empty"
        case .matchesRegex: "matches regex"
        case .isOnOrAfter: "is on or after"
        case .isBefore: "is before"
        }
    }

    /// Comparators that ignore the value field.
    var ignoresValue: Bool {
        self == .isEmpty || self == .isNotEmpty
    }
}

// MARK: - Condition

/// One field/comparator/value test.
struct FilterCondition: Equatable, Codable, Identifiable, Sendable {
    var id = UUID()
    var field: FilterField
    var comparator: FilterComparator
    var value: String

    func matches(_ document: WritingDocument, now: Date) -> Bool {
        if field.isDate {
            return matchesDate(document, now: now)
        }

        let candidates = textCandidates(of: document)

        switch comparator {
        case .isEmpty:
            return candidates.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .isNotEmpty:
            return candidates.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .is:
            return candidates.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        case .isNot:
            return !candidates.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        case .contains:
            return candidates.contains { $0.localizedCaseInsensitiveContains(value) }
        case .doesNotContain:
            return !candidates.contains { $0.localizedCaseInsensitiveContains(value) }
        case .matchesRegex:
            return matchesRegex(candidates)
        case .isOnOrAfter, .isBefore:
            // Not meaningful on a text field; treated as no match rather than a crash.
            return false
        }
    }

    // MARK: - Private

    /// The strings this condition tests. A missing property yields one empty string
    /// so `isEmpty` has something to be true about.
    private func textCandidates(of document: WritingDocument) -> [String] {
        switch field {
        case .title:
            [document.title]
        case .body:
            [document.body]
        case .tag:
            document.tags.isEmpty ? [""] : document.tags
        case let .property(key):
            [document.property(key)?.displayString ?? ""]
        case .isPinned:
            [document.isPinned ? "true" : "false"]
        case .isOrganised:
            [document.isOrganised ? "true" : "false"]
        case .modifiedAt, .createdAt:
            []
        }
    }

    private func matchesDate(_ document: WritingDocument, now: Date) -> Bool {
        let subject = field == .createdAt ? document.createdAt : document.modifiedAt
        guard let boundary = RelativeDate.resolve(value, now: now) else { return false }

        switch comparator {
        case .isOnOrAfter: return subject >= boundary
        case .isBefore: return subject < boundary
        default: return false
        }
    }

    /// An invalid pattern matches nothing. User-authored regexes are expected to be
    /// wrong sometimes, and a filter is not a place to throw.
    private func matchesRegex(_ candidates: [String]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: value) else { return false }
        return candidates.contains { candidate in
            let range = NSRange(location: 0, length: (candidate as NSString).length)
            return regex.firstMatch(in: candidate, range: range) != nil
        }
    }
}

// MARK: - Group

/// A nested group of conditions, so a view can express "all of these, and any of
/// those" the way Notion or Airtable filters do.
struct FilterGroup: Equatable, Codable, Identifiable, Sendable {
    enum Logic: String, Equatable, Codable, CaseIterable, Sendable {
        case all
        case any

        var label: String {
            self == .all ? "All" : "Any"
        }
    }

    var id = UUID()
    var logic: Logic
    var conditions: [FilterCondition]
    var groups: [FilterGroup]

    init(
        id: UUID = UUID(),
        logic: Logic,
        conditions: [FilterCondition],
        groups: [FilterGroup] = []
    ) {
        self.id = id
        self.logic = logic
        self.conditions = conditions
        self.groups = groups
    }

    /// An empty group matches everything, so a brand-new view shows all documents
    /// rather than an empty list the user has to debug.
    func matches(_ document: WritingDocument, now: Date) -> Bool {
        let results = conditions.map { $0.matches(document, now: now) }
            + groups.map { $0.matches(document, now: now) }

        guard !results.isEmpty else { return true }
        return logic == .all ? results.allSatisfy(\.self) : results.contains(true)
    }
}

// MARK: - Sort

enum SavedViewSort: String, Equatable, Codable, CaseIterable, Sendable {
    case recentlyModified
    case oldestModified
    case titleAscending
    case titleDescending

    var label: String {
        switch self {
        case .recentlyModified: "Recently modified"
        case .oldestModified: "Oldest first"
        case .titleAscending: "Title A–Z"
        case .titleDescending: "Title Z–A"
        }
    }

    func sorted(_ documents: [WritingDocument]) -> [WritingDocument] {
        switch self {
        case .recentlyModified:
            documents.sorted { $0.modifiedAt > $1.modifiedAt }
        case .oldestModified:
            documents.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAscending:
            documents.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            documents.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }
}

// MARK: - Saved View

/// A named, persisted filter over documents.
struct SavedView: Equatable, Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var filter: FilterGroup
    var sort: SavedViewSort
    /// SF Symbol shown in the sidebar.
    var symbolName: String
    /// Named accent for the sidebar row.
    var colorName: String
    /// Property keys shown as columns in the list.
    var visibleProperties: [String]

    init(
        id: UUID = UUID(),
        name: String,
        filter: FilterGroup,
        sort: SavedViewSort = .recentlyModified,
        symbolName: String = "line.3.horizontal.decrease.circle",
        colorName: String = "accent",
        visibleProperties: [String] = []
    ) {
        self.id = id
        self.name = name
        self.filter = filter
        self.sort = sort
        self.symbolName = symbolName
        self.colorName = colorName
        self.visibleProperties = visibleProperties
    }

    /// Filters and sorts `documents`. Trashed documents never appear in a view —
    /// they are reachable only from Trash.
    func apply(to documents: [WritingDocument], now: Date = Date()) -> [WritingDocument] {
        let matching = documents.filter { !$0.isTrashed && filter.matches($0, now: now) }
        return sort.sorted(matching)
    }
}
