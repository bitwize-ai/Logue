import Foundation
@testable import Logue
import Testing

/// Whether the saved audio file may be read back as the meeting's timeline.
///
/// This is the decision the long-recording pass rests on: it stamps what it finds in the file over
/// the live transcript, which is only right when the file *is* the meeting. Getting it wrong is
/// silent — a plausible transcript at the wrong times, replacing one that had them right.
@Suite("Trusting the saved recording as the session timeline")
struct SavedRecordingTrustTests {
    private typealias Sources = RecordingSessionManager.CaptureSources
    private typealias Saved = RecordingSessionManager.SavedRecording
    private typealias Placement = CaptureSegmentTimeline.Placement

    private let file = URL(fileURLWithPath: "/tmp/logue-test-audio.wav")
    private let other = URL(fileURLWithPath: "/tmp/logue-test-audio-2.wav")

    private func unbroken(_ duration: TimeInterval) -> [Placement] {
        [Placement(fileStart: 0, duration: duration, sessionStart: 0)]
    }

    // MARK: - Which files can be saved untouched

    @Test("One source running throughout is saved as it is")
    func loneUnbrokenSourceIsMovedUntouched() {
        var sources = Sources()
        sources.micURL = file
        sources.micPlacements = unbroken(900)

        #expect(!sources.needsComposing)
        #expect(sources.soleSource?.url == file)
    }

    @Test("One source that was muted has to be laid out first")
    func mutedSourceMustBeComposed() {
        var sources = Sources()
        sources.micURL = file
        sources.micPlacements = [
            Placement(fileStart: 0, duration: 120, sessionStart: 0),
            Placement(fileStart: 120, duration: 60, sessionStart: 600),
        ]

        #expect(sources.needsComposing)
    }

    @Test("One source that joined late has to be laid out first")
    func lateSourceMustBeComposed() {
        var sources = Sources()
        sources.systemURL = file
        sources.systemPlacements = [Placement(fileStart: 0, duration: 600, sessionStart: 300)]

        #expect(sources.needsComposing)
    }

    @Test("Two sources are always composed — neither file is the meeting on its own")
    func twoSourcesAlwaysCompose() {
        var sources = Sources()
        sources.systemURL = file
        sources.systemPlacements = unbroken(900)
        sources.micURL = other
        sources.micPlacements = unbroken(900)

        #expect(sources.needsComposing)
        #expect(sources.soleSource == nil)
    }

    @Test("Nothing recorded means nothing to compose")
    func noSourcesNeedNothing() {
        let sources = Sources()
        #expect(sources.isEmpty)
        #expect(!sources.needsComposing)
        #expect(sources.soleSource == nil)
    }

    // MARK: - What the pass is allowed to do with the result

    @Test("A file laid on the session timeline may be read back as the whole session")
    func timelineFileIsTrusted() {
        let saved = Saved.onSessionTimeline(file)
        #expect(saved.describesSessionTimeline)
        #expect(saved.url == file)
    }

    @Test("A raw fallback is saved but never read back for its timings")
    func rawFallbackIsNotTrusted() {
        // Composition failed: the audio is all there, but a muted stretch means its timings do not
        // describe the meeting. Reading it back would stamp a whole session at the wrong times.
        let saved = Saved.rawFallback(file)
        #expect(!saved.describesSessionTimeline)
        #expect(saved.url == file)
    }

    @Test("Nothing saved is nothing to read")
    func noneIsNotTrusted() {
        let saved = Saved.none
        #expect(!saved.describesSessionTimeline)
        #expect(saved.url == nil)
    }

    // MARK: - The flows the check exists for

    @Test("A long online meeting whose system audio was switched off is not trusted")
    func systemAudioSwitchedOffIsNotTrusted() {
        // The flow that defeated measuring this against the elapsed clock: the capture device zeroes
        // its own clock when it stops, so the session read as zero seconds long and every check
        // against it passed. What the file is cannot be recovered from a device that stopped.
        var sources = Sources()
        sources.systemURL = file
        sources.systemPlacements = [Placement(fileStart: 0, duration: 1800, sessionStart: 0)]
        sources.micURL = other
        sources.micPlacements = [Placement(fileStart: 0, duration: 9000, sessionStart: 1800)]

        #expect(sources.needsComposing)
        // Composed, it is the timeline; if composing fails it is a raw fallback and stays unread.
        #expect(!Saved.rawFallback(file).describesSessionTimeline)
    }

    @Test("A four-hour recording muted near the end is not trusted as a raw file")
    func lateMuteIsNotTrusted() {
        var sources = Sources()
        sources.micURL = file
        sources.micPlacements = [
            Placement(fileStart: 0, duration: 14000, sessionStart: 0),
            Placement(fileStart: 14000, duration: 120, sessionStart: 14300),
        ]

        #expect(sources.needsComposing)
    }
}
