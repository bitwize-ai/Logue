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
}
