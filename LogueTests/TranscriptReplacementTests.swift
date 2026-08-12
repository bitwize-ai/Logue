import Foundation
@testable import Logue
import Testing

@Suite("Transcript replacement after batch ASR")
struct TranscriptReplacementTests {
    // MARK: - Helpers

    private func segment(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end)
    }

    // MARK: - Full coverage

    @Test("Batch output replaces the whole session when it heard the whole session")
    func replacesEntireSessionWhenFullyHeard() {
        let existing = [
            segment("streaming one", 0, 10),
            segment("streaming two", 10, 20),
        ]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("batch", 0, 20)],
            sessionStart: 0,
            heardDuration: nil
        )

        #expect(result.map(\.text) == ["batch"])
    }

    @Test("Earlier recording sessions are left alone")
    func preservesEarlierSessions() {
        let existing = [
            segment("first session", 0, 30),
            segment("second session streaming", 40, 70),
        ]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("second session batch", 0, 30)],
            sessionStart: 40,
            heardDuration: nil
        )

        #expect(result.map(\.text) == ["first session", "second session batch"])
        #expect(result[1].startTime == 40)
        #expect(result[1].endTime == 70)
    }

    // MARK: - Partial coverage (the 30-minute truncation)

    @Test("Transcript past the point the batch pass stopped hearing survives")
    func keepsTailBeyondBatchCoverage() {
        let cap: TimeInterval = 1800
        let existing = [
            segment("early streaming", 60, 70),
            segment("just before the cap", cap - 20, cap - 10),
            segment("after the cap", cap + 5, cap + 15),
            segment("much later", cap + 900, cap + 910),
        ]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("batch up to the cap", 0, cap - 5)],
            sessionStart: 0,
            heardDuration: cap
        )

        #expect(result.map(\.text) == ["batch up to the cap", "after the cap", "much later"])
    }

    @Test("Partial coverage is measured from the session start, not the meeting start")
    func coverageIsSessionRelative() {
        let existing = [
            segment("first session", 0, 100),
            segment("heard by batch", 200, 260),
            segment("not heard by batch", 400, 460),
        ]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("batch", 0, 90)],
            sessionStart: 150,
            heardDuration: 100 // batch heard 150s–250s of the meeting timeline
        )

        #expect(result.map(\.text) == ["first session", "batch", "not heard by batch"])
        #expect(result[1].startTime == 150)
    }

    @Test("A segment straddling the coverage boundary is not duplicated")
    func doesNotDuplicateStraddlingSegment() {
        let existing = [segment("straddles the boundary", 95, 105)]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("batch", 0, 99)],
            sessionStart: 0,
            heardDuration: 100
        )

        #expect(result.map(\.text) == ["batch"])
    }

    @Test("Merged output is ordered by start time")
    func outputIsSorted() {
        let existing = [
            segment("tail", 500, 510),
            segment("earlier session", 0, 10),
        ]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("b2", 100, 110), segment("b1", 0, 10)],
            sessionStart: 20,
            heardDuration: 200
        )

        #expect(result.map(\.startTime) == [0, 20, 120, 500])
    }

    @Test("An empty batch result never wipes the session")
    func emptyBatchKeepsStreamingTranscript() {
        let existing = [segment("streaming", 0, 10)]

        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [],
            sessionStart: 0,
            heardDuration: 0
        )

        #expect(result.map(\.text) == ["streaming"])
    }
}
