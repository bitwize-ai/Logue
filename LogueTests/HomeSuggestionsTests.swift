import Foundation
@testable import Logue
import Testing

/// The chips under the greeting. A generic suggestion is one the user scrolls past,
/// so the rule worth guarding is that every chip on a stocked workspace names
/// something that is actually in it.
@Suite("HomeSuggestions")
struct HomeSuggestionsTests {
    private static let stocked = HomeSuggestions.Inputs(
        unsummarizedMeetingTitle: "Q3 Review",
        overdueCount: 3,
        meetingsToday: 2,
        hasAnyContent: true
    )

    @Test("Never more than the maximum, on either path")
    func neverMoreThanTheMaximum() {
        #expect(HomeSuggestions.chips(for: Self.stocked).count <= HomeSuggestions.maximum)

        // The stocked path cannot exceed the cap by construction — it appends at most one
        // chip per condition. The first-run list is the one that can: it is written by
        // hand, so it is the one worth asserting against.
        let empty = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: nil, overdueCount: 0, meetingsToday: 0, hasAnyContent: false
        )
        #expect(HomeSuggestions.chips(for: empty).count <= HomeSuggestions.maximum)
    }

    @Test("A hand-written first-run list longer than the cap is still trimmed")
    func firstRunChipsAreCappedNotJustShort() {
        // Guards the early return specifically: if `firstRunChips` grows a fourth entry,
        // the empty workspace must still render at most `maximum` of them.
        #expect(
            Array(HomeSuggestions.firstRunChips.prefix(HomeSuggestions.maximum)).count
                <= HomeSuggestions.maximum
        )
        let empty = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: nil, overdueCount: 0, meetingsToday: 0, hasAnyContent: false
        )
        #expect(
            HomeSuggestions.chips(for: empty)
                == Array(HomeSuggestions.firstRunChips.prefix(HomeSuggestions.maximum))
        )
    }

    @Test("An unsummarized meeting is named, not described generically")
    func theUnsummarizedMeetingIsNamed() {
        let chips = HomeSuggestions.chips(for: Self.stocked)
        #expect(chips.contains { $0.label.contains("Q3 Review") })
        #expect(chips.contains { $0.prompt.contains("Summarize the meeting") })
    }

    @Test("Ordering is fixed, so chips do not shuffle between renders")
    func orderingIsStable() {
        let first = HomeSuggestions.chips(for: Self.stocked)
        let second = HomeSuggestions.chips(for: Self.stocked)
        #expect(first == second)
        #expect(first.first?.label.contains("Q3 Review") == true)
    }

    @Test("An empty workspace gets the first-run chips instead")
    func emptyWorkspaceGetsFirstRunChips() {
        let empty = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: nil, overdueCount: 0, meetingsToday: 0, hasAnyContent: false
        )
        let chips = HomeSuggestions.chips(for: empty)
        #expect(!chips.isEmpty)
        #expect(chips.contains { $0.label == "What can you do?" })
    }

    @Test("A stocked but quiet workspace still offers something")
    func aQuietWorkspaceStillOffersSomething() {
        let quiet = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: nil, overdueCount: 0, meetingsToday: 0, hasAnyContent: true
        )
        #expect(HomeSuggestions.chips(for: quiet) == [
            HomeSuggestions.Chip(label: "What can you do?", prompt: "What can you do?"),
        ])
    }

    @Test("Only the conditions that hold produce chips")
    func onlyTrueConditionsProduceChips() {
        let overdueOnly = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: nil, overdueCount: 4, meetingsToday: 0, hasAnyContent: true
        )
        let chips = HomeSuggestions.chips(for: overdueOnly)
        #expect(chips.count == 1)
        #expect(chips.first?.label == "What’s overdue?")
    }

    @Test("A hostile meeting title is sanitized before it reaches a chip label")
    func hostileTitlesAreSanitizedInLabels() {
        let hostile = HomeSuggestions.Inputs(
            unsummarizedMeetingTitle: "Q3\nReview",
            overdueCount: 0,
            meetingsToday: 0,
            hasAnyContent: true
        )
        let chips = HomeSuggestions.chips(for: hostile)
        #expect(chips.first?.label.contains("\n") == false)
        #expect(chips.first?.prompt.contains("\n") == false)
    }
}
