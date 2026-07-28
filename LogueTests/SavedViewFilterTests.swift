import Foundation
@testable import Logue
import Testing

@Suite("SavedViewFilter")
struct SavedViewFilterTests {
    private func document(
        _ title: String,
        properties: [String: PropertyValue] = [:],
        tags: [String] = [],
        modified: Date = Date(),
        trashed: Bool = false
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.tags = tags
        doc.modifiedAt = modified
        doc.isTrashed = trashed
        for (key, value) in properties {
            doc.setProperty(key, value: value)
        }
        return doc
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Comparators

    @Test("is matches an exact property value")
    func isComparator() {
        let condition = FilterCondition(field: .property("status"), comparator: .is, value: "Active")
        #expect(condition.matches(document("A", properties: ["status": .text("Active")]), now: now))
        #expect(!condition.matches(document("B", properties: ["status": .text("Done")]), now: now))
    }

    @Test("is matching is case-insensitive")
    func isCaseInsensitive() {
        let condition = FilterCondition(field: .property("status"), comparator: .is, value: "active")
        #expect(condition.matches(document("A", properties: ["status": .text("Active")]), now: now))
    }

    @Test("isNot inverts is")
    func isNotComparator() {
        let condition = FilterCondition(field: .property("status"), comparator: .isNot, value: "Done")
        #expect(condition.matches(document("A", properties: ["status": .text("Active")]), now: now))
        #expect(!condition.matches(document("B", properties: ["status": .text("Done")]), now: now))
    }

    @Test("contains matches a substring")
    func containsComparator() {
        let condition = FilterCondition(field: .title, comparator: .contains, value: "report")
        #expect(condition.matches(document("Quarterly Report"), now: now))
        #expect(!condition.matches(document("Meeting Notes"), now: now))
    }

    @Test("isEmpty matches a missing property")
    func isEmptyComparator() {
        let condition = FilterCondition(field: .property("status"), comparator: .isEmpty, value: "")
        #expect(condition.matches(document("A"), now: now))
        #expect(!condition.matches(document("B", properties: ["status": .text("Active")]), now: now))
    }

    @Test("isNotEmpty matches a present property")
    func isNotEmptyComparator() {
        let condition = FilterCondition(field: .property("status"), comparator: .isNotEmpty, value: "")
        #expect(condition.matches(document("B", properties: ["status": .text("Active")]), now: now))
        #expect(!condition.matches(document("A"), now: now))
    }

    @Test("A tag is matched by the tags field")
    func tagsField() {
        let condition = FilterCondition(field: .tag, comparator: .is, value: "urgent")
        #expect(condition.matches(document("A", tags: ["urgent", "later"]), now: now))
        #expect(!condition.matches(document("B", tags: ["later"]), now: now))
    }

    // MARK: - Regex

    @Test("A regex comparator matches")
    func regexComparator() {
        let condition = FilterCondition(field: .title, comparator: .matchesRegex, value: "^Q[0-9] ")
        #expect(condition.matches(document("Q3 Planning"), now: now))
        #expect(!condition.matches(document("Annual Planning"), now: now))
    }

    @Test("An invalid regex matches nothing rather than crashing")
    func invalidRegexIsSafe() {
        let condition = FilterCondition(field: .title, comparator: .matchesRegex, value: "[unclosed")
        #expect(!condition.matches(document("anything"), now: now))
    }

    // MARK: - Relative dates

    @Test("today matches a document modified today")
    func relativeToday() {
        let condition = FilterCondition(field: .modifiedAt, comparator: .isOnOrAfter, value: "today")
        #expect(condition.matches(document("A", modified: now), now: now))
        #expect(!condition.matches(
            document("B", modified: now.addingTimeInterval(-3 * 86400)), now: now
        ))
    }

    @Test("A week-ago expression resolves relative to now")
    func relativeWeekAgo() {
        let condition = FilterCondition(
            field: .modifiedAt, comparator: .isOnOrAfter, value: "one week ago"
        )
        #expect(condition.matches(document("A", modified: now.addingTimeInterval(-2 * 86400)), now: now))
        #expect(!condition.matches(
            document("B", modified: now.addingTimeInterval(-30 * 86400)), now: now
        ))
    }

    @Test("Relative date expressions are recognised")
    func relativeExpressionsParse() {
        for expression in ["today", "yesterday", "one week ago", "one month ago"] {
            #expect(RelativeDate.resolve(expression, now: now) != nil, "\(expression) should parse")
        }
    }

    @Test("An unrecognised date expression resolves to nil")
    func unknownExpression() {
        #expect(RelativeDate.resolve("whenever", now: now) == nil)
    }

    @Test("An ISO date is accepted")
    func isoDateAccepted() {
        #expect(RelativeDate.resolve("2026-01-15", now: now) != nil)
    }

    // MARK: - Groups

    @Test("An all group requires every condition")
    func allGroup() {
        let group = FilterGroup(logic: .all, conditions: [
            FilterCondition(field: .property("status"), comparator: .is, value: "Active"),
            FilterCondition(field: .title, comparator: .contains, value: "report"),
        ])
        #expect(group.matches(
            document("Weekly Report", properties: ["status": .text("Active")]), now: now
        ))
        #expect(!group.matches(
            document("Weekly Report", properties: ["status": .text("Done")]), now: now
        ))
    }

    @Test("An any group requires one condition")
    func anyGroup() {
        let group = FilterGroup(logic: .any, conditions: [
            FilterCondition(field: .property("status"), comparator: .is, value: "Active"),
            FilterCondition(field: .title, comparator: .contains, value: "report"),
        ])
        #expect(group.matches(
            document("Weekly Report", properties: ["status": .text("Done")]), now: now
        ))
        #expect(!group.matches(
            document("Meeting Notes", properties: ["status": .text("Done")]), now: now
        ))
    }

    @Test("Groups nest")
    func nestedGroups() {
        let group = FilterGroup(
            logic: .all,
            conditions: [FilterCondition(field: .title, comparator: .contains, value: "q")],
            groups: [
                FilterGroup(logic: .any, conditions: [
                    FilterCondition(field: .property("status"), comparator: .is, value: "Active"),
                    FilterCondition(field: .property("status"), comparator: .is, value: "Review"),
                ]),
            ]
        )
        #expect(group.matches(document("Q3", properties: ["status": .text("Review")]), now: now))
        #expect(!group.matches(document("Q3", properties: ["status": .text("Done")]), now: now))
    }

    @Test("An empty group matches everything")
    func emptyGroupMatchesAll() {
        #expect(FilterGroup(logic: .all, conditions: []).matches(document("A"), now: now))
    }

    // MARK: - Saved view

    @Test("A saved view filters and sorts documents, excluding trash")
    func savedViewApplies() {
        let view = SavedView(
            name: "Active",
            filter: FilterGroup(logic: .all, conditions: [
                FilterCondition(field: .property("status"), comparator: .is, value: "Active"),
            ]),
            sort: .titleAscending
        )
        let documents = [
            document("Zeta", properties: ["status": .text("Active")]),
            document("Alpha", properties: ["status": .text("Active")]),
            document("Done thing", properties: ["status": .text("Done")]),
            document("Trashed", properties: ["status": .text("Active")], trashed: true),
        ]

        let result = view.apply(to: documents, now: now)
        #expect(result.map(\.title) == ["Alpha", "Zeta"])
    }

    @Test("A saved view round-trips through persistence")
    func savedViewRoundTrips() throws {
        let view = SavedView(
            name: "Active",
            filter: FilterGroup(logic: .any, conditions: [
                FilterCondition(field: .tag, comparator: .is, value: "urgent"),
            ]),
            sort: .recentlyModified,
            symbolName: "star",
            colorName: "blue"
        )
        let decoded = try JSONDecoder().decode(SavedView.self, from: JSONEncoder().encode(view))
        #expect(decoded == view)
    }

    @Test("Sorting by recently modified puts the newest first")
    func sortRecentlyModified() {
        let view = SavedView(name: "All", filter: FilterGroup(logic: .all, conditions: []), sort: .recentlyModified)
        let documents = [
            document("Old", modified: now.addingTimeInterval(-86400)),
            document("New", modified: now),
        ]
        #expect(view.apply(to: documents, now: now).map(\.title) == ["New", "Old"])
    }
}
