import Foundation
@testable import Logue
import Testing

@Suite("Speaker alignment")
struct SpeakerAlignmentTests {
    // MARK: - Helpers

    private func speakerSegment(_ id: String, _ start: TimeInterval, _ end: TimeInterval) -> SpeakerSegment {
        SpeakerSegment(speakerId: id, startTime: start, endTime: end)
    }

    private func transcript(
        _ text: String,
        _ start: TimeInterval,
        _ end: TimeInterval,
        label: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: label)
    }

    private let names = ["a": "Alice", "b": "Bob", "c": "Cleo"]

    // MARK: - Overlap voting

    @Test("The majority-overlap speaker wins even when the segment midpoint lands on another")
    func overlapBeatsMidpoint() {
        // Alice holds 9.2s of this segment, Bob 0.8s — but the midpoint (5.0) falls inside Bob's
        // brief interjection, which is exactly what midpoint-nearest matching gets wrong.
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 0, 10)],
            speakerSegments: [
                speakerSegment("a", 0, 4.6),
                speakerSegment("b", 4.6, 5.4),
                speakerSegment("a", 5.4, 10),
            ],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice"])
    }

    @Test("A near-tie in overlap keeps the previous segment's speaker")
    func ambiguousOverlapPrefersContinuity() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 0, 1), transcript("two", 1, 2)],
            speakerSegments: [
                speakerSegment("a", 0, 1),
                speakerSegment("a", 1, 1.45),
                speakerSegment("b", 1.45, 2),
            ],
            speakerNamesByID: names
        )

        // Bob has marginally more overlap on the second segment (0.55 vs 0.45), but not enough
        // to justify a switch — without the guard this would read Alice, Bob.
        #expect(result.map(\.speakerLabel) == ["Alice", "Alice"])
    }

    @Test("A near-tie with no previous speaker takes the greater overlap")
    func ambiguousOverlapWithoutPreviousTakesWinner() {
        let result = SpeakerAlignment.align(
            segments: [transcript("two", 1, 2)],
            speakerSegments: [speakerSegment("a", 1, 1.45), speakerSegment("b", 1.45, 2)],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Bob"])
    }

    @Test("A decisive overlap still switches speakers")
    func decisiveOverlapSwitches() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 0, 1), transcript("two", 1, 2)],
            speakerSegments: [speakerSegment("a", 0, 1), speakerSegment("b", 1, 2)],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice", "Bob"])
    }

    // MARK: - Splitting at speaker boundaries

    @Test("A segment spanning two speakers is split at the boundary")
    func splitsAtSpeakerBoundary() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one two three four five six seven eight nine ten", 0, 10)],
            speakerSegments: [speakerSegment("a", 0, 5), speakerSegment("b", 5, 10)],
            speakerNamesByID: names
        )

        #expect(result.count == 2)
        #expect(result.map(\.speakerLabel) == ["Alice", "Bob"])
        #expect(result[0].startTime == 0)
        #expect(result[0].endTime == 5)
        #expect(result[1].startTime == 5)
        #expect(result[1].endTime == 10)
    }

    @Test("Splitting distributes the text without losing or duplicating words")
    func splitPreservesEveryWord() {
        let original = "one two three four five six seven eight nine ten"
        let result = SpeakerAlignment.align(
            segments: [transcript(original, 0, 10)],
            speakerSegments: [speakerSegment("a", 0, 5), speakerSegment("b", 5, 10)],
            speakerNamesByID: names
        )

        let rejoined = result.map(\.text).joined(separator: " ")
        #expect(rejoined == original)
    }

    @Test("A segment spanning three speakers splits into three parts")
    func splitsIntoThreeParts() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one two three four five six", 0, 9)],
            speakerSegments: [
                speakerSegment("a", 0, 3),
                speakerSegment("b", 3, 6),
                speakerSegment("c", 6, 9),
            ],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice", "Bob", "Cleo"])
    }

    @Test("A segment with fewer words than speaker ranges is left whole")
    func tooFewWordsToSplit() {
        // Splitting "hi" across two speakers would have to invent or drop text.
        let result = SpeakerAlignment.align(
            segments: [transcript("hi", 0, 10)],
            speakerSegments: [speakerSegment("a", 0, 5), speakerSegment("b", 5, 10)],
            speakerNamesByID: names
        )

        #expect(result.count == 1)
        #expect(result[0].text == "hi")
    }

    @Test("A brushing overlap below the meaningful threshold does not trigger a split")
    func negligibleOverlapDoesNotSplit() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one two three four", 0, 5.05)],
            speakerSegments: [speakerSegment("a", 0, 5), speakerSegment("b", 5, 10)],
            speakerNamesByID: names
        )

        #expect(result.count == 1)
        #expect(result[0].speakerLabel == "Alice")
    }

    // MARK: - No transcript loss

    @Test("A segment shorter than the split minimum is never dropped")
    func shortSegmentSurvives() {
        let result = SpeakerAlignment.align(
            segments: [transcript("Yes.", 0, 0.3)],
            speakerSegments: [speakerSegment("a", 0, 0.3)],
            speakerNamesByID: names
        )

        #expect(result.count == 1)
        #expect(result[0].text == "Yes.")
        #expect(result[0].speakerLabel == "Alice")
    }

    @Test("Alignment never reduces the number of transcript segments")
    func neverLosesSegments() {
        let segments = [
            transcript("a", 0, 0.2),
            transcript("b", 0.2, 0.5),
            transcript("c", 0.5, 12),
            transcript("d", 12, 12.1),
        ]
        let result = SpeakerAlignment.align(
            segments: segments,
            speakerSegments: [speakerSegment("a", 0, 6), speakerSegment("b", 6, 13)],
            speakerNamesByID: names
        )

        #expect(result.count >= segments.count)
    }

    // MARK: - Existing labels are protected

    @Test("An already-labelled segment is neither relabelled nor split")
    func existingLabelIsPreserved() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one two three four", 0, 10, label: "You")],
            speakerSegments: [speakerSegment("a", 0, 5), speakerSegment("b", 5, 10)],
            speakerNamesByID: names
        )

        #expect(result.count == 1)
        #expect(result[0].speakerLabel == "You")
    }

    @Test("A protected label is not rewritten by smoothing")
    func smoothingSkipsProtectedLabels() {
        let result = SpeakerAlignment.align(
            segments: [
                transcript("one", 0, 1),
                transcript("two", 1, 1.5, label: "You"),
                transcript("three", 1.5, 2.5),
            ],
            speakerSegments: [
                speakerSegment("a", 0, 1),
                speakerSegment("a", 1, 1.5),
                speakerSegment("a", 1.5, 2.5),
            ],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice", "You", "Alice"])
    }

    // MARK: - Island smoothing

    @Test("A brief single-segment island adopts the speaker flanking it")
    func smoothsBriefIsland() {
        let result = SpeakerAlignment.align(
            segments: [
                transcript("one", 0, 1),
                transcript("two", 1, 1.5),
                transcript("three", 1.5, 2.5),
            ],
            speakerSegments: [
                speakerSegment("a", 0, 1),
                speakerSegment("b", 1, 1.5),
                speakerSegment("a", 1.5, 2.5),
            ],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice", "Alice", "Alice"])
    }

    @Test("A substantial island keeps its own speaker")
    func keepsSubstantialIsland() {
        // 2 seconds of speech is a real turn, not diarization flapping.
        let result = SpeakerAlignment.align(
            segments: [
                transcript("one", 0, 1),
                transcript("two", 1, 3),
                transcript("three", 3, 4),
            ],
            speakerSegments: [
                speakerSegment("a", 0, 1),
                speakerSegment("b", 1, 3),
                speakerSegment("a", 3, 4),
            ],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice", "Bob", "Alice"])
    }

    // MARK: - Fallback window

    @Test("A segment just past a speaker's end still borrows that speaker")
    func fallbackWithinTolerance() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 5.2, 6)],
            speakerSegments: [speakerSegment("a", 0, 5)],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == ["Alice"])
    }

    @Test("A segment far from every speaker is left unlabelled")
    func noFallbackBeyondTolerance() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 10, 11)],
            speakerSegments: [speakerSegment("a", 0, 5)],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == [nil])
    }

    // MARK: - Degenerate input

    @Test("With no speaker segments the transcript is returned untouched")
    func noSpeakerSegments() {
        let segments = [transcript("one", 0, 1), transcript("two", 1, 2)]
        let result = SpeakerAlignment.align(
            segments: segments,
            speakerSegments: [],
            speakerNamesByID: names
        )

        #expect(result.map(\.text) == ["one", "two"])
        #expect(result.map(\.speakerLabel) == [nil, nil])
    }

    @Test("An empty transcript yields an empty result")
    func emptyTranscript() {
        let result = SpeakerAlignment.align(
            segments: [],
            speakerSegments: [speakerSegment("a", 0, 5)],
            speakerNamesByID: names
        )

        #expect(result.isEmpty)
    }

    @Test("A speaker id with no name mapping does not produce a label")
    func unmappedSpeakerID() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 0, 1)],
            speakerSegments: [speakerSegment("ghost", 0, 1)],
            speakerNamesByID: names
        )

        #expect(result.map(\.speakerLabel) == [nil])
    }

    @Test("A single speaker labels the whole transcript")
    func singleSpeaker() {
        let result = SpeakerAlignment.align(
            segments: [transcript("one", 0, 1), transcript("two", 1, 2), transcript("three", 2, 3)],
            speakerSegments: [speakerSegment("a", 0, 3)],
            speakerNamesByID: names
        )

        #expect(result.allSatisfy { $0.speakerLabel == "Alice" })
    }
}
