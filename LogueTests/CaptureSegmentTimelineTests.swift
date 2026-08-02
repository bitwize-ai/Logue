import Foundation
@testable import Logue
import Testing

@Suite("Mic placement in the playback mix")
struct CaptureSegmentTimelineTests {
    @Test("A mic running the whole meeting is one placement at the start")
    func singleRunFromTheStart() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)

        let placements = timeline.finalized(fileDuration: 600)

        #expect(placements == [.init(fileStart: 0, duration: 600, sessionStart: 0)])
    }

    @Test("A mic switched on part-way through is placed where it joined")
    func lateStartIsPlacedAtItsJoinTime() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 300, fileDuration: 0)

        let placements = timeline.finalized(fileDuration: 120)

        #expect(placements == [.init(fileStart: 0, duration: 120, sessionStart: 300)])
    }

    @Test("Every mute/unmute cycle is placed on its own, so nothing after the first drifts")
    func mutingDoesNotShiftLaterAudio() {
        var timeline = CaptureSegmentTimeline()

        // Talks 0–120s, muted until 420s, talks again for 60s, muted, talks once more at 600s.
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        timeline.sourceStopped(fileDuration: 120)
        timeline.sourceStarted(atSessionTime: 420, fileDuration: 120)
        timeline.sourceStopped(fileDuration: 180)
        timeline.sourceStarted(atSessionTime: 600, fileDuration: 180)

        let placements = timeline.finalized(fileDuration: 210)

        // The file holds 210s of audio in three runs; the meeting spans 630s.
        #expect(placements == [
            .init(fileStart: 0, duration: 120, sessionStart: 0),
            .init(fileStart: 120, duration: 60, sessionStart: 420),
            .init(fileStart: 180, duration: 30, sessionStart: 600),
        ])
        #expect(placements.map(\.duration).reduce(0, +) == 210)
        // Each placement reads from where the previous one ended — the file has no gaps in it.
        #expect(placements[1].fileStart == placements[0].fileStart + placements[0].duration)
        #expect(placements[2].fileStart == placements[1].fileStart + placements[1].duration)
    }

    @Test("A mic muted at the end contributes nothing extra")
    func trailingMuteAddsNoPlacement() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        timeline.sourceStopped(fileDuration: 90)

        let placements = timeline.finalized(fileDuration: 90)

        #expect(placements.count == 1)
        #expect(placements[0].duration == 90)
    }

    @Test("An unmute that recorded nothing is dropped rather than placed empty")
    func emptyActivationIsDropped() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        timeline.sourceStopped(fileDuration: 45)
        timeline.sourceStarted(atSessionTime: 300, fileDuration: 45)

        let placements = timeline.finalized(fileDuration: 45)

        #expect(placements == [.init(fileStart: 0, duration: 45, sessionStart: 0)])
    }

    @Test("A repeated start does not open a second overlapping activation")
    func repeatedStartIsIgnored() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        timeline.sourceStarted(atSessionTime: 30, fileDuration: 30)

        let placements = timeline.finalized(fileDuration: 100)

        #expect(placements == [.init(fileStart: 0, duration: 100, sessionStart: 0)])
    }

    @Test("A mic that never ran produces no placements")
    func neverStartedIsEmpty() {
        let timeline = CaptureSegmentTimeline()
        #expect(timeline.finalized(fileDuration: 0).isEmpty)
    }

    // MARK: - Whether the raw file can stand in for the meeting

    @Test("A source that ran once from the start needs no composing")
    func unbrokenSourceFromZeroMatchesTheTimeline() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        let placements = timeline.finalized(fileDuration: 900)

        #expect(CaptureSegmentTimeline.fileMatchesSessionTimeline(placements))
    }

    @Test("A source that joined late does not match, however unbroken it was after that")
    func lateJoinDoesNotMatch() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 240, fileDuration: 0)
        let placements = timeline.finalized(fileDuration: 900)

        #expect(!CaptureSegmentTimeline.fileMatchesSessionTimeline(placements))
    }

    @Test("A source that was muted once does not match")
    func mutedSourceDoesNotMatch() {
        var timeline = CaptureSegmentTimeline()
        timeline.sourceStarted(atSessionTime: 0, fileDuration: 0)
        timeline.sourceStopped(fileDuration: 100)
        timeline.sourceStarted(atSessionTime: 400, fileDuration: 100)
        let placements = timeline.finalized(fileDuration: 200)

        #expect(!CaptureSegmentTimeline.fileMatchesSessionTimeline(placements))
    }

    @Test("A source that never recorded does not match — there is no file to stand in")
    func noPlacementsDoNotMatch() {
        #expect(!CaptureSegmentTimeline.fileMatchesSessionTimeline([]))
    }
}
