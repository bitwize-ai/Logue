import Foundation
@testable import Logue
import Testing

@Suite("Transcript realignment")
struct TranscriptRealignmentTests {
    private func segment(
        _ text: String,
        _ start: TimeInterval,
        _ end: TimeInterval,
        speaker: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: speaker)
    }

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval)
        -> TranscriptRealignment.TimedWord
    {
        .init(text: text, startTime: start, endTime: end)
    }

    @Test("Better words replace the text without changing the shape")
    func wordsLandInTheirSegments() {
        let live = [
            segment("that ours came in higher", 0, 5),
            segment("than we expected", 5, 10),
        ]
        let words = [
            word("Quarterly ", 0.1, 0.9), word("numbers ", 1.0, 1.8),
            word("came ", 2.0, 2.4), word("in ", 2.5, 2.7), word("higher", 2.8, 3.4),
            word("than ", 5.2, 5.5), word("we ", 5.6, 5.8), word("expected", 6.0, 6.6),
        ]

        let result = TranscriptRealignment.realign(live: live, words: words)

        #expect(result.count == live.count, "the number of lines must not change")
        #expect(result[0].text == "Quarterly numbers came in higher")
        #expect(result[1].text == "than we expected")
    }

    @Test("Identity and timing are preserved exactly")
    func structureIsUntouched() {
        let live = [segment("draft", 0, 5, speaker: "Speaker 1")]
        let result = TranscriptRealignment.realign(live: live, words: [word("final", 1, 2)])

        #expect(result[0].id == live[0].id, "a changed id would scroll the reader somewhere else")
        #expect(result[0].startTime == live[0].startTime)
        #expect(result[0].endTime == live[0].endTime)
        #expect(result[0].speakerLabel == "Speaker 1")
    }

    @Test("A line no word lands in keeps what it had")
    func emptySegmentsKeepTheirText() {
        let live = [segment("kept as heard", 0, 5), segment("replaced", 10, 15)]
        let result = TranscriptRealignment.realign(live: live, words: [word("new", 11, 12)])

        #expect(result[0].text == "kept as heard", "blanking a line is worse than an imperfect one")
        #expect(result[1].text == "new")
    }

    @Test("A word straddling a boundary goes where most of it is")
    func midpointDecidesTheBoundary() {
        let live = [segment("first", 0, 5), segment("second", 5, 10)]
        // Runs 4.0–6.0, midpoint 5.0 — the second segment owns it.
        let result = TranscriptRealignment.realign(live: live, words: [word("straddling", 4.0, 6.0)])
        #expect(result[1].text == "straddling")
        #expect(result[0].text == "first")
    }

    @Test("Words heard in the gaps attach to the nearest line rather than vanishing")
    func wordsInGapsAreKept() {
        let live = [segment("one", 0, 5), segment("two", 20, 25)]
        let result = TranscriptRealignment.realign(live: live, words: [word("between", 6, 7)])
        #expect(result[0].text == "between", "dropping it would lose speech the batch pass heard")
    }

    @Test("Nothing to realign leaves the transcript alone")
    func degenerateInputs() {
        let live = [segment("untouched", 0, 5)]
        #expect(TranscriptRealignment.realign(live: live, words: []).first?.text == "untouched")
        #expect(TranscriptRealignment.realign(live: [], words: [word("x", 0, 1)]).isEmpty)
    }

    // MARK: - Sub-word tokens

    @Test("Sub-word pieces are joined before placement")
    func tokensBecomeWholeWords() {
        // Exactly what Parakeet emits: "Hundreds" as two pieces.
        let tokens = [word(" H", 0.1, 0.2), word("undreds", 0.2, 0.5), word(" of", 0.6, 0.7)]
        let joined = TranscriptRealignment.words(fromTokens: tokens)

        #expect(joined.count == 2)
        #expect(joined[0].text == " Hundreds")
        #expect(joined[0].startTime == 0.1)
        #expect(joined[0].endTime == 0.5, "a word spans all of its pieces")
    }

    @Test("A word split across a line boundary stays whole")
    func splitWordIsNotTornInTwo() {
        // "Hundreds" straddles the 0.35 boundary; as pieces it landed in both lines.
        let live = [segment("first", 0, 0.35), segment("second", 0.35, 1)]
        let tokens = [word(" H", 0.1, 0.2), word("undreds", 0.25, 0.5)]
        let joined = TranscriptRealignment.words(fromTokens: tokens)
        let result = TranscriptRealignment.realign(live: live, words: joined)

        let whole = result.map(\.text)
        #expect(whole.contains { $0.contains("Hundreds") }, "the word must survive intact")
        #expect(whole.contains { $0 == "H" } == false)
        #expect(whole.contains { $0 == "undreds" } == false)
    }

    @Test("SentencePiece word markers also start words")
    func sentencePieceMarker() {
        let tokens = [word("\u{2581}the", 0, 0.2), word("CUBE", 0.2, 0.4)]
        let joined = TranscriptRealignment.words(fromTokens: tokens)
        #expect(joined.count == 1)
    }

    // MARK: - Sentence snapping

    @Test("A line ending mid-phrase reaches forward to the sentence end")
    func snapsToSentenceEnd() {
        let segments = [
            segment("Okay, so let's", 0, 5),
            segment("use this agent to make a deck. I open it on my desktop", 5, 12),
        ]
        let snapped = TranscriptRealignment.snappedToSentences(segments)

        #expect(snapped.count == 2, "snapping must not change the number of lines")
        #expect(snapped[0].text == "Okay, so let's use this agent to make a deck.")
        #expect(snapped[1].text == "I open it on my desktop")
    }

    @Test("Identity and timing survive snapping")
    func snappingKeepsStructure() {
        let segments = [segment("and then", 0, 5), segment("we moved on. Next thing", 5, 10)]
        let snapped = TranscriptRealignment.snappedToSentences(segments)
        #expect(snapped[0].id == segments[0].id)
        #expect(snapped[0].startTime == 0)
        #expect(snapped[1].endTime == 10)
    }

    @Test("A line already ending a sentence is left alone")
    func completedLineIsUntouched() {
        let segments = [segment("All done.", 0, 5), segment("Something else. And more", 5, 10)]
        let snapped = TranscriptRealignment.snappedToSentences(segments)
        #expect(snapped[0].text == "All done.")
        #expect(snapped[1].text == "Something else. And more")
    }

    @Test("A line is never emptied to complete the one before it")
    func neverEmptiesALine() {
        let segments = [segment("trailing off", 0, 5), segment("done.", 5, 10)]
        let snapped = TranscriptRealignment.snappedToSentences(segments)
        #expect(snapped[1].text == "done.", "an empty line is worse than a line ending early")
    }

    @Test("A sentence end too far away is left where it is")
    func distantSentenceEndIsIgnored() {
        let long = String(repeating: "word ", count: 40) + "end."
        let segments = [segment("unfinished", 0, 5), segment(long, 5, 10)]
        let snapped = TranscriptRealignment.snappedToSentences(segments)
        #expect(snapped[0].text == "unfinished", "a line must not swallow the one after it")
    }
}
