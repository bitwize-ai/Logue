import Foundation
import Testing

@testable import Logue

/// The review findings on #58 that are decidable without a microphone.
///
/// Each fails against the code as it stood at `3ce89922`, which is the only property that makes
/// a regression test worth keeping. Cases that already had a home — `TranscriptRealignmentTests`
/// owns the offset, `TranscriptSentenceMergeTests` owns the speaker guard — were left there
/// rather than restated here.
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

    // MARK: - Merging cannot join two speakers

    @Test("Lines are not merged while the system tap is live")
    func mergeRefusedWhileTheSystemTapIsLive() {
        // Every segment carries `speakerLabel: nil` during recording, so the cross-speaker guard
        // is always nil == nil and always passes. The system tap carries every remote
        // participant, so two consecutive lines from it can be two people, and the merge welded
        // them into one line with one id that nothing downstream could split.
        //
        // Gating on the mic being live *as well* had this backwards: a meeting with the mic
        // muted has the most speakers and would have had the least protection.
        let previous = segment("so what I think is", start: 0, end: 2)
        let next = segment("actually the opposite", start: 2.3, end: 4)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: previous, next: next, mayCarryTwoSpeakers: true
            ) == false
        )
    }

    @Test("Lines are still merged when the system tap is not running")
    func mergeStillHappensWithoutTheSystemTap() {
        // The split-sentence join is the feature; an in-person recording keeps it.
        let previous = segment("the agent helps assemble", start: 0, end: 2)
        let next = segment("it into something you can judge", start: 2.3, end: 4)

        #expect(
            TranscriptSentenceMerge.shouldMerge(
                previous: previous, next: next, mayCarryTwoSpeakers: false
            )
        )
    }

    @Test("Snapping never moves text across a session boundary")
    func snappingStaysInsideItsSession() {
        // `realign` was bounded; this runs on its output and moves words between neighbouring
        // lines, so the last line of session one and the first of session two are neighbours.
        // A sentence "finished" across that join rewrites a line the current session did not
        // produce.
        let live = [
            segment("the first session ends mid", start: 0, end: 300),
            segment("thought. and the second begins", start: 301, end: 310),
        ]

        let snapped = TranscriptRealignment.snappedToSentences(live, sessionStart: 301)

        #expect(snapped[0].text == "the first session ends mid")
        #expect(snapped[1].text == "thought. and the second begins")
    }

    @Test("Snapping still tidies lines inside one session")
    func snappingStillWorksWithinASession() {
        let live = [
            segment("the agent helps assemble", start: 0, end: 2),
            segment("it. into something you can judge", start: 2, end: 5),
        ]

        let snapped = TranscriptRealignment.snappedToSentences(live)

        #expect(snapped[0].text == "the agent helps assemble it.")
        #expect(snapped[1].text == "into something you can judge")
    }

    // MARK: - Whether a queued capture survives a refusal

    @Test("A refusal that clears on its own keeps the request", arguments: [
        RecordingStartOutcome.rebuildingInterruptedSession,
        .previousSessionStopping,
        .alreadyStarting,
    ])
    func selfClearingRefusalsKeepTheRequest(outcome: RecordingStartOutcome) {
        // `.previousSessionStopping` is the one the previous rule missed: pressing Stop and
        // immediately clicking the next calendar event dropped the capture in silence, because
        // the view re-derived the reason from `isRecovering` and that was false.
        #expect(outcome.clearsOnItsOwn)
    }

    @Test("A refusal that will not resolve itself drops the request", arguments: [
        RecordingStartOutcome.microphoneDenied,
        .engineUnavailable,
        .captureFailed,
    ])
    func permanentRefusalsDropTheRequest(outcome: RecordingStartOutcome) {
        // A kept request outlives its refusal: `.task(id:)` runs again on the next open, so
        // denying the microphone once left a request armed to start recording the next time the
        // user merely opened that meeting to read it.
        #expect(outcome.clearsOnItsOwn == false)
    }

    @Test("A started session is not a refusal and keeps nothing")
    func startedKeepsNothing() {
        #expect(RecordingStartOutcome.started.started)
        #expect(RecordingStartOutcome.started.clearsOnItsOwn == false)
    }

    @Test("Each blocked recorder state maps to the refusal that describes it", arguments: [
        (
            RecordingSessionManager.RecordingState.recovering,
            RecordingStartOutcome.rebuildingInterruptedSession
        ),
        (.stopping, .previousSessionStopping),
        (.starting, .alreadyStarting),
    ])
    func blockedStatesMapToTheirRefusal(
        state: RecordingSessionManager.RecordingState,
        expected: RecordingStartOutcome
    ) {
        #expect(RecordingStartOutcome(refusedIn: state) == expected)
    }
}
