import Foundation
@testable import Logue
import SwiftUI
import Testing

@Suite("Speaker rename and merge")
@MainActor
struct SpeakerRenameTests {
    // MARK: - Fixtures

    /// A two-speaker meeting where diarization split one person across both rows —
    /// the situation that produced the duplicate-name crash.
    private func twoSpeakerMeeting() -> MeetingNote {
        var meeting = MeetingNote(title: "Standup")
        meeting.speakers = [
            Speaker(id: "s1", name: "Speaker 1", color: Speaker.generateColor(for: 0)),
            Speaker(id: "s2", name: "Speaker 2", color: Speaker.generateColor(for: 1)),
        ]
        meeting.speakerSegments = [
            SpeakerSegment(speakerId: "s1", startTime: 0, endTime: 5, text: "first"),
            SpeakerSegment(speakerId: "s2", startTime: 5, endTime: 10, text: "second"),
            SpeakerSegment(speakerId: "s1", startTime: 10, endTime: 15, text: "third"),
        ]
        meeting.segments = [
            TranscriptSegment(text: "first", startTime: 0, endTime: 5, speakerLabel: "Speaker 1"),
            TranscriptSegment(text: "second", startTime: 5, endTime: 10, speakerLabel: "Speaker 2"),
            TranscriptSegment(text: "third", startTime: 10, endTime: 15, speakerLabel: "Speaker 1"),
        ]
        meeting.hasSpeakerData = true
        return meeting
    }

    // MARK: - Plain rename

    @Test("Renaming to an unused name renames in place without merging")
    func renameToUnusedName() {
        let result = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")

        #expect(result.speakers.count == 2)
        #expect(result.speakers.map(\.name).sorted() == ["John", "Speaker 2"])
        #expect(result.segments.map(\.speakerLabel) == ["John", "Speaker 2", "John"])
        // Speaker segment ownership is untouched — no rows were combined.
        #expect(result.speakerSegments.map(\.speakerId) == ["s1", "s2", "s1"])
    }

    @Test("Renaming preserves the speaker's stable id")
    func renamePreservesID() {
        let result = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")
        #expect(result.speakers.first { $0.name == "John" }?.id == "s1")
    }

    // MARK: - Merge on duplicate name

    @Test("Renaming to an existing speaker's name merges the two speakers")
    func renameToExistingNameMerges() {
        let renamed = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")
        let merged = renamed.renamingSpeaker(from: "Speaker 2", to: "John")

        #expect(merged.speakers.count == 1)
        #expect(merged.speakers.first?.name == "John")
    }

    @Test("Merging relabels every transcript segment to the surviving name")
    func mergeRelabelsTranscript() {
        let renamed = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")
        let merged = renamed.renamingSpeaker(from: "Speaker 2", to: "John")

        #expect(merged.segments.allSatisfy { $0.speakerLabel == "John" })
    }

    @Test("Merging remaps speaker segments onto the surviving speaker id")
    func mergeRemapsSpeakerSegments() {
        let renamed = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")
        let merged = renamed.renamingSpeaker(from: "Speaker 2", to: "John")

        let survivingID = merged.speakers.first?.id
        #expect(survivingID != nil)
        #expect(merged.speakerSegments.allSatisfy { $0.speakerId == survivingID })
        // No speaker segments are lost in the merge.
        #expect(merged.speakerSegments.count == 3)
    }

    @Test("Merging preserves speaker segment timings and text")
    func mergePreservesSegmentPayload() {
        let renamed = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "John")
        let merged = renamed.renamingSpeaker(from: "Speaker 2", to: "John")

        #expect(merged.speakerSegments.map(\.startTime) == [0, 5, 10])
        #expect(merged.speakerSegments.map(\.text) == ["first", "second", "third"])
    }

    // MARK: - The crash itself

    @Test("A name-keyed color map survives a meeting holding duplicate speaker names")
    func colorMapToleratesDuplicateNames() {
        // Reproduces already-persisted meetings broken by the original bug: two
        // speaker rows share a name, so a name-keyed dictionary must not trap.
        var meeting = twoSpeakerMeeting()
        meeting.speakers = [
            Speaker(id: "s1", name: "John", color: Speaker.generateColor(for: 0)),
            Speaker(id: "s2", name: "John", color: Speaker.generateColor(for: 1)),
        ]

        let colors = meeting.speakerColorsByName

        #expect(colors.count == 1)
        #expect(colors["John"] != nil)
    }

    @Test("Colour map covers every distinct speaker name")
    func colorMapCoversDistinctNames() {
        let colors = twoSpeakerMeeting().speakerColorsByName

        #expect(colors.count == 2)
        #expect(colors["Speaker 1"] != nil)
        #expect(colors["Speaker 2"] != nil)
    }

    // MARK: - No-ops

    @Test("Renaming to the same name changes nothing")
    func renameToSameNameIsNoOp() {
        let original = twoSpeakerMeeting()
        let result = original.renamingSpeaker(from: "Speaker 1", to: "Speaker 1")

        #expect(result.speakers.map(\.name) == original.speakers.map(\.name))
        #expect(result.segments.map(\.speakerLabel) == original.segments.map(\.speakerLabel))
    }

    @Test("An empty or whitespace-only new name is rejected")
    func blankNameIsNoOp() {
        let original = twoSpeakerMeeting()

        #expect(original.renamingSpeaker(from: "Speaker 1", to: "").speakers.map(\.name)
            == original.speakers.map(\.name))
        #expect(original.renamingSpeaker(from: "Speaker 1", to: "   ").speakers.map(\.name)
            == original.speakers.map(\.name))
    }

    @Test("Surrounding whitespace is trimmed from the new name")
    func newNameIsTrimmed() {
        let result = twoSpeakerMeeting().renamingSpeaker(from: "Speaker 1", to: "  John  ")
        #expect(result.speakers.contains { $0.name == "John" })
    }

    @Test("Renaming a speaker that does not exist changes nothing")
    func unknownSpeakerIsNoOp() {
        let original = twoSpeakerMeeting()
        let result = original.renamingSpeaker(from: "Nobody", to: "John")

        #expect(result.speakers.map(\.name) == original.speakers.map(\.name))
        #expect(result.segments.map(\.speakerLabel) == original.segments.map(\.speakerLabel))
    }

    @Test("Merging into a name held by a speaker with no segments still collapses the rows")
    func mergeIntoSegmentlessSpeaker() {
        var meeting = twoSpeakerMeeting()
        meeting.speakers.append(Speaker(id: "s3", name: "John", color: Speaker.generateColor(for: 2)))

        let merged = meeting.renamingSpeaker(from: "Speaker 1", to: "John")

        #expect(merged.speakers.count == 2)
        #expect(merged.speakers.filter { $0.name == "John" }.count == 1)
        #expect(merged.segments.map(\.speakerLabel) == ["John", "Speaker 2", "John"])
    }
}
