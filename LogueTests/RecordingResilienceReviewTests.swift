import Foundation
import Testing

@testable import Logue

/// The review findings on #58 that are decidable without a microphone.
///
/// Each fails against the code as it stood at `3ce89922`. The three covered here are the ones
/// whose failure mode is losing a user's recording or their transcript; the rest are wiring
/// changes in the capture pipeline, which needs a device.
@Suite("Recording resilience review")
struct RecordingResilienceReviewTests {
    private func segment(
        _ text: String,
        start: TimeInterval,
        end: TimeInterval,
        speaker: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text, startTime: start, endTime: end, speakerLabel: speaker, confidence: 1
        )
    }

    // MARK: - Realignment cannot reach an earlier session

    @Test("A second session's words never land in the first session's lines")
    func realignmentStaysInsideItsSession() {
        // The reported case was a missing offset. Shifting the words fixed that but left `live`
        // as the whole meeting, so a session producing no live lines of its own — the speech
        // gate admitting nothing — put every shifted word past the end of every earlier line,
        // and the uncapped nearest-segment fallback concatenated the entire second session into
        // the last line of the first.
        let sessionOne = [
            segment("the first five minutes", start: 0, end: 150),
            segment("still the first session", start: 150, end: 300),
        ]
        let words = [
            TranscriptRealignment.TimedWord(text: "second ", startTime: 0, endTime: 1),
            TranscriptRealignment.TimedWord(text: "session ", startTime: 1, endTime: 2),
        ]

        let result = TranscriptRealignment.realign(live: sessionOne, words: words, sessionStart: 301)

        #expect(result == sessionOne)
    }

    @Test("A session's own lines still receive its words")
    func realignmentStillAppliesWithinTheSession() {
        // The bound must not disable the feature it guards.
        let live = [
            segment("earlier session", start: 0, end: 100),
            segment("mis heard", start: 301, end: 305),
        ]
        let words = [
            TranscriptRealignment.TimedWord(text: "misheard ", startTime: 1, endTime: 2),
            TranscriptRealignment.TimedWord(text: "words", startTime: 2, endTime: 3),
        ]

        let result = TranscriptRealignment.realign(live: live, words: words, sessionStart: 301)

        #expect(result[0].text == "earlier session")
        #expect(result[1].text == "misheard words")
    }

    // MARK: - Merging cannot join two speakers

    @Test("Lines are not merged while both capture sources are live")
    func mergeRefusedWhenTwoSourcesAreLive() {
        // During recording every segment carries `speakerLabel: nil`, so the cross-speaker guard
        // is always nil == nil and always passes. With the mic and the system tap feeding one
        // analyzer, a local utterance and a remote reply became one line carrying one id and one
        // speaker, and nothing downstream could split it again.
        let previous = segment("so what I think is", start: 0, end: 2)
        let next = segment("actually the opposite", start: 2.3, end: 4)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: previous, next: next, mayCarryTwoSpeakers: true
            ) == false
        )
    }

    @Test("Lines are still merged when only one source is live")
    func mergeStillHappensWithOneSource() {
        let previous = segment("the agent helps assemble", start: 0, end: 2)
        let next = segment("it into something you can judge", start: 2.3, end: 4)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: previous, next: next, mayCarryTwoSpeakers: false
            )
        )
    }

    @Test("A labelled speaker change is still refused")
    func labelledSpeakerChangeStillRefused() {
        // The original guard has to keep working after diarization has labelled the segments.
        let previous = segment("so what I think is", start: 0, end: 2, speaker: "Speaker 1")
        let next = segment("actually the opposite", start: 2.3, end: 4, speaker: "Speaker 2")

        #expect(TranscriptSentenceMerge.shouldMerge(previous: previous, next: next) == false)
    }
}
