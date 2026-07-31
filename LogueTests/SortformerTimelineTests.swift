import Foundation
@testable import Logue
import Testing

@Suite("Sortformer timeline normalization")
struct SortformerTimelineTests {
    // MARK: - Helpers

    private func update(_ index: Int, _ start: TimeInterval, _ end: TimeInterval) -> SortformerSpeakerUpdate {
        SortformerSpeakerUpdate(
            speakerIndex: index,
            speakerName: "Speaker \(index + 1)",
            startTime: start,
            endTime: end
        )
    }

    // MARK: - Fragment filtering

    @Test("Fragments below the minimum duration are discarded")
    func dropsShortFragments() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 5),
            update(1, 5, 5.2),
            update(0, 5.2, 10),
        ])

        #expect(result.allSatisfy { $0.endTime - $0.startTime >= AppConstants.Diarization.minSpeakerSegmentDuration })
        #expect(result.allSatisfy { $0.speakerIndex == 0 })
    }

    // MARK: - Merging

    @Test("Adjacent segments from the same speaker are merged across a small gap")
    func mergesAdjacentSameSpeaker() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 3),
            update(0, 3.1, 6),
        ])

        #expect(result.count == 1)
        #expect(result[0].startTime == 0)
        #expect(result[0].endTime == 6)
    }

    @Test("Segments from different speakers are not merged")
    func doesNotMergeDifferentSpeakers() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 3),
            update(1, 3.1, 6),
        ])

        #expect(result.count == 2)
        #expect(result.map(\.speakerIndex) == [0, 1])
    }

    // MARK: - Alternation collapsing

    @Test("A rapid A-B-A alternation collapses to the dominant speaker")
    func collapsesRapidAlternation() {
        // Three turns inside 0.8s is diarization flapping, not conversation.
        let result = SortformerTimeline.normalize([
            update(0, 0, 5),
            update(1, 5, 5.3),
            update(0, 5.3, 5.6),
            update(1, 5.6, 12),
        ])

        #expect(result.map(\.speakerIndex) == [0, 1])
    }

    @Test("A genuine slow alternation is preserved")
    func preservesSlowAlternation() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 5),
            update(1, 5, 10),
            update(0, 10, 15),
        ])

        #expect(result.map(\.speakerIndex) == [0, 1, 0])
    }

    // MARK: - Continuity

    @Test("Overlapping segments have their start clamped forward")
    func clampsOverlappingStarts() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 6),
            update(1, 4, 10),
        ])

        #expect(result.count == 2)
        #expect(result[0].endTime <= result[1].startTime)
    }

    @Test("A gap narrow enough to be model jitter is closed")
    func closesJitterGap() throws {
        let result = SortformerTimeline.normalize([
            update(0, 0, 10),
            update(1, 11, 20),
        ])

        try #require(result.count == 2)
        #expect(result[1].startTime == 10 + AppConstants.Diarization.timelineMaxGap)
    }

    @Test("A long silence is left as silence rather than given to the next speaker")
    func doesNotCloseLongSilence() throws {
        // Closing this would start Speaker 2 at 10.5 and hand them 19.5s they were not speaking for.
        // Alignment compares true transcript times against these, so anything transcribed in the
        // silence would be labelled Speaker 2 with full confidence.
        let result = SortformerTimeline.normalize([
            update(0, 0, 10),
            update(1, 30, 40),
        ])

        try #require(result.count == 2)
        #expect(result[1].startTime == 30)
    }

    @Test("The same speaker either side of a long silence is not joined across it")
    func doesNotMergeSameSpeakerAcrossLongSilence() throws {
        let result = SortformerTimeline.normalize([
            update(0, 0, 10),
            update(0, 30, 40),
        ])

        try #require(result.count == 2)
        #expect(result[0].endTime == 10)
        #expect(result[1].startTime == 30)
    }

    @Test("Output is ordered by start time")
    func outputIsSorted() {
        let result = SortformerTimeline.normalize([
            update(1, 10, 15),
            update(0, 0, 5),
            update(2, 20, 25),
        ])

        #expect(result.map(\.startTime) == result.map(\.startTime).sorted())
    }

    @Test("A segment fully swallowed by the preceding one is dropped rather than inverted")
    func dropsSwallowedSegment() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 10),
            update(1, 2, 4),
        ])

        #expect(result.allSatisfy { $0.endTime > $0.startTime })
    }

    // MARK: - Speaker count is never forced

    @Test("A three-speaker timeline keeps all three speakers")
    func threeSpeakersSurvive() {
        // Guards against reintroducing a hardcoded two-speaker collapse.
        let result = SortformerTimeline.normalize([
            update(0, 0, 20),
            update(1, 20, 40),
            update(2, 40, 60),
        ])

        #expect(Set(result.map(\.speakerIndex)) == [0, 1, 2])
    }

    @Test("A quiet but real third speaker is not folded into the others")
    func quietThirdSpeakerSurvives() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 60),
            update(1, 60, 120),
            update(2, 120, 124),
        ])

        #expect(Set(result.map(\.speakerIndex)) == [0, 1, 2])
    }

    // MARK: - Degenerate input

    @Test("Empty input yields empty output")
    func emptyInput() {
        #expect(SortformerTimeline.normalize([]).isEmpty)
    }

    @Test("A single segment passes through unchanged")
    func singleSegment() {
        let result = SortformerTimeline.normalize([update(0, 0, 10)])

        #expect(result.count == 1)
        #expect(result[0].startTime == 0)
        #expect(result[0].endTime == 10)
    }

    @Test("Input consisting only of fragments yields nothing")
    func allFragments() {
        let result = SortformerTimeline.normalize([
            update(0, 0, 0.1),
            update(1, 0.1, 0.2),
        ])

        #expect(result.isEmpty)
    }
}
