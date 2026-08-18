import Foundation
@testable import Logue
import Testing

@Suite("Recording checkpoint")
struct RecordingCheckpointTests {
    private func checkpoint(meetingID: UUID = UUID()) -> RecordingCheckpoint {
        RecordingCheckpoint(
            meetingID: meetingID,
            sessionStart: Date(timeIntervalSince1970: 1_000_000),
            timeOffset: 0,
            segments: [TranscriptSegment(text: "hello", startTime: 0, endTime: 2)],
            micPlacements: [.init(fileStart: 0, duration: 120, sessionStart: 0)],
            systemPlacements: [.init(fileStart: 0, duration: 60, sessionStart: 60)],
            micFileName: "mic.wav",
            systemFileName: "system.caf",
            writtenAt: Date(timeIntervalSince1970: 1_000_120)
        )
    }

    @Test("A checkpoint survives a round trip")
    func roundTrips() throws {
        let original = checkpoint()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(RecordingCheckpoint.self, from: data)
        #expect(restored == original)
    }

    @Test("What lands on disk is not readable as plaintext")
    func writtenCheckpointIsEncrypted() throws {
        let id = UUID()
        defer { InProgressRecordingStore.clear(meetingID: id) }

        var point = checkpoint(meetingID: id)
        point = RecordingCheckpoint(
            meetingID: id,
            sessionStart: point.sessionStart,
            timeOffset: point.timeOffset,
            segments: [TranscriptSegment(text: "a confidential sentence", startTime: 0, endTime: 2)],
            micPlacements: point.micPlacements,
            systemPlacements: point.systemPlacements,
            micFileName: point.micFileName,
            systemFileName: point.systemFileName,
            writtenAt: point.writtenAt
        )
        try RecordingCheckpoint.write(point)

        let url = try InProgressRecordingStore.directory(for: id).appending(component: "checkpoint.json")
        let raw = try Data(contentsOf: url)
        let asText = String(bytes: raw, encoding: .utf8) ?? ""
        #expect(
            asText.contains("a confidential sentence") == false,
            "the transcript is sitting on disk in the clear for the length of every meeting"
        )
        guard case let .checkpoint(read) = RecordingCheckpoint.read(meetingID: id) else {
            Issue.record("the checkpoint should still be readable by the app that wrote it")
            return
        }
        #expect(read.segments.first?.text == "a confidential sentence")
    }

    @Test("Placements survive, because they are the part that cannot be recomputed")
    func placementsSurvive() throws {
        let original = checkpoint()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(RecordingCheckpoint.self, from: data)
        #expect(restored.systemPlacements.first?.sessionStart == 60)
        #expect(restored.micPlacements.first?.duration == 120)
    }

    @Test("Covered duration is the furthest point any placement reaches")
    func coveredDurationSpansBothSources() {
        #expect(abs(checkpoint().coveredDuration - 120) < 0.001)
    }

    @Test("A checkpoint with no placements covers nothing")
    func emptyCheckpointCoversNothing() {
        let empty = RecordingCheckpoint(
            meetingID: UUID(),
            sessionStart: Date(timeIntervalSince1970: 0),
            timeOffset: 0,
            segments: [],
            micPlacements: [],
            systemPlacements: [],
            micFileName: nil,
            systemFileName: nil,
            writtenAt: Date(timeIntervalSince1970: 0)
        )
        #expect(empty.coveredDuration == 0, "nothing recovered may claim any of the meeting")
    }

    @Test("Writing and reading a checkpoint from disk round-trips")
    func writesAndReadsFromDisk() throws {
        let id = UUID()
        defer { InProgressRecordingStore.clear(meetingID: id) }

        let original = checkpoint(meetingID: id)
        try RecordingCheckpoint.write(original)
        guard case let .checkpoint(restored) = RecordingCheckpoint.read(meetingID: id) else {
            Issue.record("a checkpoint just written should read back")
            return
        }
        #expect(restored == original)
    }

    @Test("A meeting with no checkpoint reads as absent, not as unreadable")
    func missingCheckpointIsAbsent() {
        // The two are told apart because recovery deletes the recording on one of them.
        let id = UUID()
        defer { InProgressRecordingStore.clear(meetingID: id) }
        #expect(RecordingCheckpoint.read(meetingID: id) == .absent)
    }

    @Test("A checkpoint that will not decrypt reads as unreadable, not as absent")
    func corruptCheckpointIsUnreadable() throws {
        // The case a Mac restored from a backup hits: the key is stored
        // WhenUnlockedThisDeviceOnly, so a fresh one cannot open the old file. Reading that
        // as "no checkpoint" removed the working directory and the audio inside it.
        let id = UUID()
        defer { InProgressRecordingStore.clear(meetingID: id) }

        let url = try InProgressRecordingStore.directory(for: id)
            .appending(component: "checkpoint.json")
        try Data("not an encrypted checkpoint".utf8).write(to: url)

        #expect(RecordingCheckpoint.read(meetingID: id) == .unreadable)
    }

    @Test("A cleared session leaves nothing pending")
    func clearingRemovesThePendingMarker() throws {
        let id = UUID()
        try RecordingCheckpoint.write(checkpoint(meetingID: id))
        #expect(InProgressRecordingStore.pendingMeetingIDs().contains(id))

        InProgressRecordingStore.clear(meetingID: id)
        #expect(
            InProgressRecordingStore.pendingMeetingIDs().contains(id) == false,
            "a stopped session must not look interrupted at the next launch"
        )
    }
}
