import Foundation
@testable import Logue
import Testing

@Suite("Recording recovery")
struct RecordingRecoveryTests {
    private func segment(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end)
    }

    @Test("A recovery covering part of a session may not replace all of it")
    func partialRecoveryIsBounded() {
        let existing = [
            segment("first half", 0, 120),
            segment("second half", 120, 240),
        ]

        // The recovered audio reaches 120s, so the pass over it speaks for 120s and no further.
        let result = TranscriptReplacement.merged(
            existing: existing,
            batch: [segment("recovered", 0, 120)],
            sessionStart: 0,
            heardDuration: 120
        )

        #expect(
            result.contains { $0.text == "second half" },
            "transcript past what the recovered audio covers must survive"
        )
    }

    @Test("Covered duration is the furthest point any placement reaches")
    func coveredDurationSpansBothSources() {
        let point = RecordingCheckpoint(
            meetingID: UUID(),
            sessionStart: Date(timeIntervalSince1970: 0),
            timeOffset: 0,
            segments: [],
            micPlacements: [.init(fileStart: 0, duration: 30, sessionStart: 0)],
            systemPlacements: [.init(fileStart: 0, duration: 45, sessionStart: 90)],
            micFileName: "mic.wav",
            systemFileName: "system.caf",
            writtenAt: Date(timeIntervalSince1970: 135)
        )
        #expect(abs(point.coveredDuration - 135) < 0.001)
    }

    @Test("A working directory with no checkpoint is pending but unrecoverable")
    func unreadableCheckpointIsDiscarded() throws {
        let id = UUID()
        defer { InProgressRecordingStore.clear(meetingID: id) }

        _ = try InProgressRecordingStore.directory(for: id)
        #expect(InProgressRecordingStore.pendingMeetingIDs().contains(id))
        #expect(
            RecordingCheckpoint.read(meetingID: id) == .absent,
            "a session that crashed inside its first checkpoint has nothing to rebuild from"
        )
    }

    @Test("A recovered timeline rebuilds the placements it was given")
    func timelineRebuildsFromPlacements() {
        let placements: [CaptureSegmentTimeline.Placement] = [
            .init(fileStart: 0, duration: 60, sessionStart: 0),
            .init(fileStart: 60, duration: 30, sessionStart: 120),
        ]
        let timeline = CaptureSegmentTimeline(placements: placements)
        #expect(timeline.placements == placements)
        #expect(
            CaptureSegmentTimeline.fileMatchesSessionTimeline(timeline.placements) == false,
            "a session with a gap in it cannot have its raw file stand in for the timeline"
        )
    }

    @Test("A recovered single unbroken run is still the session timeline")
    func unbrokenRunIsTheTimeline() {
        let timeline = CaptureSegmentTimeline(
            placements: [.init(fileStart: 0, duration: 90, sessionStart: 0)]
        )
        #expect(CaptureSegmentTimeline.fileMatchesSessionTimeline(timeline.placements))
    }
}
