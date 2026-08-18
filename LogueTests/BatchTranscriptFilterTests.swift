import Foundation
@testable import Logue
import Testing

@Suite("Batch transcript VAD filter")
struct BatchTranscriptFilterTests {
    private func segment(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end)
    }

    private func region(_ start: TimeInterval, _ end: TimeInterval) -> BatchTranscriptFilter.SpeechRegion {
        .init(startTime: start, endTime: end)
    }

    // MARK: - The case that lost a meeting

    @Test("Speech the VAD missed is kept when it would take most of the transcript with it")
    func doesNotDeleteMostOfTheTranscript() {
        // Exactly what happened live: three transcribed segments, ninety tokens of real speech, and
        // a VAD that only found the loud stretch. Dropping two of three deleted the microphone half
        // of the meeting.
        let segments = [
            segment("system audio, loud and clear", 0, 20),
            segment("someone talking into the microphone", 25, 45),
            segment("still talking into the microphone", 45, 59),
        ]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(0, 20)])

        #expect(result.segments.count == 3, "two thirds of a transcript is not a hallucination")
        #expect(result.distrustedVAD)
        #expect(result.removed == 0)
    }

    @Test("A VAD that finds nothing at all is disregarded")
    func emptyOverlapKeepsEverything() {
        let segments = [segment("one", 0, 5), segment("two", 5, 10)]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(100, 120)])
        #expect(result.segments.count == 2)
        #expect(result.distrustedVAD)
    }

    // MARK: - What the filter is actually for

    @Test("A stray segment in silence is still removed")
    func removesAnIsolatedHallucination() {
        let segments = [
            segment("real one", 0, 10),
            segment("real two", 10, 20),
            segment("invented during silence", 40, 42),
        ]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(0, 20)])

        #expect(result.segments.count == 2)
        #expect(result.removed == 1)
        #expect(result.distrustedVAD == false)
        #expect(result.segments.contains { $0.text == "invented during silence" } == false)
    }

    @Test("Exactly half surviving is still trusted")
    func halfIsTheBoundary() {
        let segments = [
            segment("kept one", 0, 5),
            segment("kept two", 5, 10),
            segment("dropped one", 40, 45),
            segment("dropped two", 45, 50),
        ]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(0, 10)])
        #expect(result.segments.count == 2)
        #expect(result.distrustedVAD == false)
    }

    // MARK: - Boundaries

    @Test("A segment touching the very edge of a speech region counts as overlapping")
    func partialOverlapCounts() {
        let segments = [segment("straddles the edge", 18, 25)]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(0, 20)])
        #expect(result.segments.count == 1)
    }

    @Test("Touching end-to-start is not an overlap")
    func abuttingIsNotOverlap() {
        // Three inside the speech region so the majority guard stays out of the way, and one
        // starting exactly where speech ended.
        let segments = [
            segment("during one", 0, 5),
            segment("during two", 5, 10),
            segment("during three", 10, 15),
            segment("after", 20, 30),
        ]
        let result = BatchTranscriptFilter.filter(segments, speechRegions: [region(0, 20)])
        #expect(result.segments.count == 3)
        #expect(result.removed == 1)
        #expect(result.segments.contains { $0.text == "after" } == false)
    }

    @Test("No segments and no regions are both handled")
    func degenerateInputs() {
        #expect(BatchTranscriptFilter.filter([], speechRegions: [region(0, 10)]).segments.isEmpty)
        let segments = [segment("only", 0, 5)]
        #expect(BatchTranscriptFilter.filter(segments, speechRegions: []).segments.count == 1)
    }
}
