import Foundation
import Testing

@testable import Logue

/// The line a tool card shows for what a tool was called with.
///
/// Both rules here were bugs before the type existed, and both only show at island width —
/// where the card is 700pt rather than a full window and the row has to hold the summary,
/// the status and the Approve and Deny buttons at once.
@Suite("ToolArgumentSummary")
struct ToolArgumentSummaryTests {
    // MARK: - Ordering

    @Test("The same arguments always produce the same line")
    func orderIsStable() {
        // It mapped over a Dictionary, which has no order, so the same call rendered
        // `query: standup, limit: 5` on one pass and `limit: 5, query: standup` on the next.
        // With the line truncated, the argument you can read changed as the view re-rendered.
        //
        // This case states the intent but does not on its own catch the regression: a
        // dictionary's iteration order is seeded per process, so within one test run the old
        // code answered consistently too. `keysAreSorted` below is the one that goes red when
        // the sort is removed — verified by removing it.
        let json = #"{"query":"standup","limit":5,"space":"Work","after":"2026-01-01"}"#
        let first = ToolArgumentSummary.summary(fromJSON: json)
        for _ in 0 ..< 20 {
            #expect(ToolArgumentSummary.summary(fromJSON: json) == first)
        }
    }

    @Test("Keys are ordered by name")
    func keysAreSorted() {
        let summary = ToolArgumentSummary.summary(fromJSON: #"{"zebra":1,"alpha":2,"mango":3}"#)
        #expect(summary == "alpha: 2, mango: 3, zebra: 1")
    }

    // MARK: - Bounds

    @Test("A huge argument cannot make the line huge")
    func totalLengthIsBounded() {
        // `update_document` carries the whole new body as an argument. lineLimit(1) hid the
        // tail, but the text was still laid out and pushed the status badge and the approval
        // buttons off the end of the row.
        let body = String(repeating: "a", count: 20_000)
        let summary = ToolArgumentSummary.summary(fromJSON: #"{"content":"\#(body)"}"#)
        #expect(summary.count <= ToolArgumentSummary.maxTotalLength)
    }

    @Test("One long value does not crowd out the others")
    func eachValueIsBoundedSeparately() {
        let long = String(repeating: "b", count: 500)
        let summary = ToolArgumentSummary.summary(fromJSON: #"{"aaa":"\#(long)","zzz":"visible"}"#)
        #expect(summary.hasPrefix("aaa: "))
        #expect(summary.contains("zzz: visible"), "the short one is still readable")
    }

    @Test("Unparseable arguments are shown, but bounded")
    func rawFallbackIsBounded() {
        // Still what the tool was called with, so it is worth showing — but the reason this
        // type exists is that nothing on this row may be unbounded.
        let notJSON = String(repeating: "x", count: 5000)
        let summary = ToolArgumentSummary.summary(fromJSON: notJSON)
        #expect(summary.isEmpty == false)
        #expect(summary.count <= ToolArgumentSummary.maxTotalLength)
    }

    @Test("Truncation never exceeds the budget it was given")
    func ellipsisFitsInsideTheBudget() {
        // The ellipsis is inside the budget rather than added to it, so a caller that sized a
        // row from the limit is not handed one character more.
        for length in [1, 2, 47, 48, 49, 200, 5000] {
            let value = String(repeating: "c", count: length)
            let summary = ToolArgumentSummary.summary(fromJSON: #"{"k":"\#(value)"}"#)
            #expect(summary.count <= ToolArgumentSummary.maxTotalLength)
        }
    }

    // MARK: - One line

    @Test("A multi-line value is flattened onto one line")
    func newlinesAreCollapsed() {
        // A document body arrives with its newlines intact, and a Text limited to one line
        // renders the first of them and hides the rest — so a multi-paragraph argument looked
        // like a short one, with no ellipsis to say otherwise.
        let summary = ToolArgumentSummary.summary(fromJSON: #"{"body":"first\nsecond\n\nthird"}"#)
        #expect(summary.contains("\n") == false)
        #expect(summary == "body: first second third")
    }

    @Test("Runs of whitespace collapse to one space")
    func whitespaceIsCollapsed() {
        let summary = ToolArgumentSummary.summary(fromJSON: #"{"t":"a     b\t\tc"}"#)
        #expect(summary == "t: a b c")
    }

    // MARK: - Nothing to show

    @Test("No arguments produce no line")
    func emptyArgumentsAreEmpty() {
        // The card checked for these itself. Answering it here means one place decides
        // whether there is anything to draw.
        #expect(ToolArgumentSummary.summary(fromJSON: "{}").isEmpty)
        #expect(ToolArgumentSummary.summary(fromJSON: "").isEmpty)
        #expect(ToolArgumentSummary.summary(fromJSON: "   ").isEmpty)
        #expect(ToolArgumentSummary.summary(fromJSON: "  {}  ").isEmpty)
    }
}
