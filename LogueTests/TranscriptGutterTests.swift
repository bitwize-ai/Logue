import Foundation
@testable import Logue
import Testing

@Suite("Transcript gutter marks")
struct TranscriptGutterTests {
    private func segment(_ text: String, _ start: TimeInterval, speaker: String? = nil) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 2, speakerLabel: speaker)
    }

    @Test("The first line always carries a mark")
    func firstLineIsMarked() {
        let segments = [segment("one", 0), segment("two", 2)]
        let marks = TranscriptGutter.marks(for: segments)
        #expect(marks[segments[0].id]?.time == "0:00")
        #expect(marks[segments[1].id] == nil, "consecutive lines read as one paragraph")
    }

    @Test("A new mark appears once the clock has moved on")
    func timeAdvancing() {
        let segments = [segment("one", 0), segment("two", 4), segment("three", 12)]
        let marks = TranscriptGutter.marks(for: segments)
        #expect(marks[segments[1].id] == nil)
        #expect(marks[segments[2].id]?.time == "0:12")
    }

    @Test("A speaker change is marked even mid-paragraph")
    func speakerChangeMarks() {
        let segments = [
            segment("one", 0, speaker: "Speaker 1"),
            segment("two", 2, speaker: "Speaker 2"),
        ]
        let marks = TranscriptGutter.marks(for: segments)
        #expect(marks[segments[1].id]?.shortSpeaker == "S2", "a turn must announce itself")
        #expect(marks[segments[1].id]?.time == "0:02")
    }

    @Test("The same speaker continuing is not re-marked")
    func sameSpeakerContinues() {
        let segments = [
            segment("one", 0, speaker: "Speaker 1"),
            segment("two", 2, speaker: "Speaker 1"),
        ]
        #expect(TranscriptGutter.marks(for: segments)[segments[1].id] == nil)
    }

    @Test("Marks do not change when speakers are added to the same segments")
    func labellingDoesNotMoveTheTimes() {
        // The point of the whole design: diarization adds names without re-cutting anything.
        let plain = [segment("one", 0), segment("two", 12), segment("three", 24)]
        let labelled = [
            segment("one", 0, speaker: "Speaker 1"),
            segment("two", 12, speaker: "Speaker 1"),
            segment("three", 24, speaker: "Speaker 1"),
        ]
        let before = TranscriptGutter.marks(for: plain).values.map(\.time).sorted()
        let after = TranscriptGutter.marks(for: labelled).values.map(\.time).sorted()
        #expect(before == after)
    }

    @Test("Going from no speaker to a speaker counts as a change")
    func nilToNamedIsAChange() {
        let segments = [segment("one", 0), segment("two", 2, speaker: "Speaker 1")]
        #expect(TranscriptGutter.marks(for: segments)[segments[1].id]?.shortSpeaker == "S1")
    }

    @Test("One speaker holding the floor is named once, not beside every timestamp")
    func nameIsPrintedOnlyWhenItChanges() {
        let segments = [
            segment("one", 0, speaker: "Speaker 1"),
            segment("two", 12, speaker: "Speaker 1"),
            segment("three", 24, speaker: "Speaker 1"),
        ]
        let marks = TranscriptGutter.marks(for: segments)
        #expect(marks[segments[0].id]?.shortSpeaker == "S1")
        #expect(marks[segments[1].id]?.shortSpeaker.isEmpty == true, "a repeated name reads as a new turn")
        #expect(marks[segments[2].id]?.shortSpeaker.isEmpty == true)
        // The times still print, so the transcript keeps its shape.
        #expect(marks[segments[1].id]?.time == "0:12")
    }

    @Test("The name returns when the floor changes hands and comes back")
    func nameReturnsAfterAnotherSpeaker() {
        let segments = [
            segment("one", 0, speaker: "Speaker 1"),
            segment("two", 12, speaker: "Speaker 2"),
            segment("three", 24, speaker: "Speaker 1"),
        ]
        let marks = TranscriptGutter.marks(for: segments)
        #expect(marks[segments[1].id]?.shortSpeaker == "S2")
        #expect(marks[segments[2].id]?.shortSpeaker == "S1")
    }
}
