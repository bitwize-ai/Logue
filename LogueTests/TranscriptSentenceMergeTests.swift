import Foundation
@testable import Logue
import Testing

@Suite("Transcript sentence merging")
struct TranscriptSentenceMergeTests {
    private func segment(
        _ text: String,
        _ start: TimeInterval,
        _ end: TimeInterval,
        speaker: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: speaker)
    }

    @Test("An unfinished line takes in the one that continues it")
    func continuationIsMerged() {
        let first = segment("The agent helps assemble", 0, 4)
        let second = segment("it into something you can judge.", 4.2, 7)
        #expect(TranscriptSentenceMerge.shouldMerge(previous: first, next: second))

        let joined = TranscriptSentenceMerge.merged(first, with: second)
        #expect(joined.text == "The agent helps assemble it into something you can judge.")
        #expect(joined.id == first.id, "the line keeps its identity so nothing scrolls")
        #expect(joined.startTime == 0)
        #expect(joined.endTime == 7)
    }

    @Test("A finished sentence stands alone")
    func completedSentenceIsNotMerged() {
        let first = segment("You own the decision.", 0, 3)
        let second = segment("So let's do a walkthrough", 3.2, 6)
        #expect(TranscriptSentenceMerge.shouldMerge(previous: first, next: second) == false)
    }

    @Test("Question and exclamation marks end sentences too")
    func otherTerminators() {
        #expect(TranscriptSentenceMerge.endsSentence("Where do you put it?"))
        #expect(TranscriptSentenceMerge.endsSentence("Exactly!"))
        #expect(TranscriptSentenceMerge.endsSentence("So really…"))
        #expect(TranscriptSentenceMerge.endsSentence("and then") == false)
    }

    @Test("A reply is never folded into the line before it")
    func speakersAreNeverMerged() {
        let first = segment("and I think that", 0, 3, speaker: "Speaker 1")
        let second = segment("no, I disagree", 3.1, 5, speaker: "Speaker 2")
        #expect(TranscriptSentenceMerge.shouldMerge(previous: first, next: second) == false)
    }

    @Test("A long silence ends the line whatever the punctuation")
    func longGapStopsMerging() {
        let first = segment("and then", 0, 3)
        let second = segment("we moved on", 8, 11)
        #expect(TranscriptSentenceMerge.shouldMerge(previous: first, next: second) == false)
    }

    @Test("A line that has run long is left alone")
    func runawayLinesAreCapped() {
        let first = segment("someone talking without pausing", 0, 29)
        let second = segment("and still going", 29.1, 40)
        #expect(TranscriptSentenceMerge.shouldMerge(previous: first, next: second) == false)
    }

    @Test("A second session's first words never extend the first session's last line")
    func mergeRefusedAcrossASessionBoundary() {
        // Pressing record again sets the new offset to `lastEnd + 1.0` — inside `maximumGap` —
        // so this was merged, rewriting a line the earlier session produced. Every label is
        // `nil` during recording, so the speaker guard does not catch it.
        let closing = segment("so what I think is", 298, 300)
        let opening = segment("actually the opposite", 301, 303)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: closing, next: opening, sessionStart: 301
            ) == false
        )
    }

    @Test("Lines inside one session are still joined")
    func mergeStillHappensWithinASession() {
        let first = segment("the agent helps assemble", 301, 303)
        let second = segment("it into something you can judge", 303.3, 305)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: first, next: second, sessionStart: 301
            )
        )
    }
}
