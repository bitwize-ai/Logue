import Foundation
@testable import Logue
import Testing

/// Detecting an in-progress `[[` link at the caret, so the editor knows when to
/// offer completions and what to replace when one is chosen.
@Suite("WikiLinkCompletion")
struct WikiLinkCompletionTests {
    private func detect(_ text: String, cursor: Int) -> WikiLinkCompletion? {
        WikiLinkCompletion.atCursor(in: text, cursor: cursor)
    }

    // MARK: - Triggering

    @Test("Typing the opening brackets triggers with an empty query")
    func triggersOnOpeningBrackets() {
        let completion = detect("see [[", cursor: 6)
        #expect(completion?.query.isEmpty == true)
    }

    @Test("Partial text after the brackets becomes the query")
    func partialQuery() {
        #expect(detect("see [[Alp", cursor: 9)?.query == "Alp")
    }

    @Test("A query may contain spaces")
    func queryWithSpaces() {
        #expect(detect("[[Project Al", cursor: 12)?.query == "Project Al")
    }

    @Test("No opening brackets means no completion")
    func noBrackets() {
        #expect(detect("plain text", cursor: 10) == nil)
    }

    @Test("A single bracket does not trigger")
    func singleBracket() {
        #expect(detect("see [", cursor: 5) == nil)
    }

    @Test("An empty document does not trigger")
    func emptyText() {
        #expect(detect("", cursor: 0) == nil)
    }

    // MARK: - Already-closed links

    @Test("A completed link does not offer completions after it")
    func closedLinkDoesNotTrigger() {
        #expect(detect("see [[Alpha]] now", cursor: 17) == nil)
    }

    @Test("The caret inside a completed link still offers completions")
    func caretInsideClosedLinkTriggers() {
        // Caret between "Alp" and "ha]]" — the user is editing the target.
        #expect(detect("[[Alpha]]", cursor: 5)?.query == "Alp")
    }

    // MARK: - Boundaries

    @Test("The caret before the brackets does not trigger")
    func caretBeforeBrackets() {
        #expect(detect("see [[Alpha", cursor: 2) == nil)
    }

    @Test("A link cannot span lines, so a newline cancels the completion")
    func newlineCancels() {
        #expect(detect("[[Alpha\nmore", cursor: 12) == nil)
    }

    @Test("The nearest opening brackets before the caret win")
    func nearestBracketsWin() {
        #expect(detect("[[First]] and [[Sec", cursor: 19)?.query == "Sec")
    }

    @Test("Typing a pipe ends completion — the user is writing display text")
    func pipeEndsCompletion() {
        #expect(detect("[[Alpha|shown", cursor: 13) == nil)
    }

    @Test("A cursor beyond the text length is rejected rather than trapping")
    func cursorOutOfBounds() {
        #expect(detect("[[Al", cursor: 99) == nil)
    }

    @Test("A negative cursor is rejected")
    func negativeCursor() {
        #expect(detect("[[Al", cursor: -1) == nil)
    }

    // MARK: - Replacement range

    @Test("The replacement range covers the brackets and the query")
    func replacementRangeCoversTrigger() throws {
        let text = "see [[Alp"
        let completion = try #require(detect(text, cursor: 9))
        #expect((text as NSString).substring(with: completion.replacementRange) == "[[Alp")
    }

    @Test("The replacement range also covers a trailing closing bracket pair")
    func replacementRangeCoversClosingBrackets() throws {
        let text = "[[Alp]]"
        let completion = try #require(detect(text, cursor: 5))
        #expect((text as NSString).substring(with: completion.replacementRange) == "[[Alp]]")
    }

    /// Guardrail: ranges are UTF-16, so a multi-UTF-16 character before the trigger
    /// must not shift them.
    @Test("Ranges stay correct with emoji before the trigger")
    func rangesWithLeadingEmoji() throws {
        let text = "👩‍💻 記録 [[Alp"
        let nsText = text as NSString
        let completion = try #require(detect(text, cursor: nsText.length))
        #expect(nsText.substring(with: completion.replacementRange) == "[[Alp")
        #expect(completion.query == "Alp")
    }

    // MARK: - Insertion

    @Test("Choosing a title produces a complete link")
    func insertionText() {
        #expect(WikiLinkCompletion.insertionText(for: "Project Alpha") == "[[Project Alpha]]")
    }

    @Test("A title containing brackets is stripped so the link stays parseable")
    func insertionStripsBrackets() {
        #expect(WikiLinkCompletion.insertionText(for: "Wei[rd]") == "[[Weird]]")
    }

    @Test("A title containing a pipe is stripped so the alias form is not forged")
    func insertionStripsPipe() {
        #expect(WikiLinkCompletion.insertionText(for: "A|B") == "[[AB]]")
    }

    @Test("A newline in a title is replaced with a space")
    func insertionFlattensNewlines() {
        #expect(WikiLinkCompletion.insertionText(for: "One\nTwo") == "[[One Two]]")
    }
}
