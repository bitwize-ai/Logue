import Foundation

/// Where each stretch of the microphone recording belongs on the meeting's timeline.
///
/// The mic writes to one continuous file across mute and unmute, with the muted stretches simply
/// absent — two minutes of talking, a five-minute mute, one more minute of talking is a three-minute
/// file. Laying that file into the playback mix as a single run puts everything after the first mute
/// five minutes early, and it gets worse with every toggle. So each activation is recorded as its
/// own placement: where it sits in the file, how long it runs, and where on the meeting it belongs.
struct MicSegmentTimeline {
    /// One uninterrupted mic activation: `duration` seconds starting `fileStart` into the mic file,
    /// belonging at `sessionStart` on the meeting's timeline.
    struct Placement: Equatable {
        let fileStart: TimeInterval
        let duration: TimeInterval
        let sessionStart: TimeInterval
    }

    private(set) var placements: [Placement] = []

    /// The activation currently recording, if the mic is live.
    private var open: (sessionStart: TimeInterval, fileStart: TimeInterval)?

    /// The mic started recording. `fileDuration` is how much audio the mic file already holds — the
    /// file's own length rather than an elapsed-time estimate, so placements cannot drift from it.
    mutating func micStarted(atSessionTime sessionStart: TimeInterval, fileDuration: TimeInterval) {
        guard open == nil else { return }
        open = (max(0, sessionStart), max(0, fileDuration))
    }

    /// The mic stopped. Closes the open activation at the file's current length.
    mutating func micStopped(fileDuration: TimeInterval) {
        guard let open else { return }
        self.open = nil
        let duration = max(0, fileDuration - open.fileStart)
        guard duration > 0 else { return }
        placements.append(
            Placement(fileStart: open.fileStart, duration: duration, sessionStart: open.sessionStart)
        )
    }

    /// Every placement, closing any activation still open at the final file length. Use at stop.
    func finalized(fileDuration: TimeInterval) -> [Placement] {
        var copy = self
        copy.micStopped(fileDuration: fileDuration)
        return copy.placements
    }
}
