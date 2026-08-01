import Foundation

/// Where each stretch of a capture source's recording belongs on the meeting's timeline.
///
/// A source writes to one continuous file across every stop and start, with the stopped stretches
/// simply absent — two minutes of talking, a five-minute mute, one more minute of talking is a
/// three-minute file. Laying that file down as a single run puts everything after the first mute
/// five minutes early, and it gets worse with every toggle. The same applies to a source that joins
/// late: its file begins when it joined, not when the meeting did.
///
/// So each activation is recorded as its own placement: where it sits in the file, how long it runs,
/// and where on the meeting it belongs. Both the microphone and the system-audio tap keep one.
struct CaptureSegmentTimeline {
    /// One uninterrupted activation: `duration` seconds starting `fileStart` into the source's file,
    /// belonging at `sessionStart` on the meeting's timeline.
    struct Placement: Equatable {
        let fileStart: TimeInterval
        let duration: TimeInterval
        let sessionStart: TimeInterval
    }

    private(set) var placements: [Placement] = []

    /// The activation currently recording, if the source is live.
    private var open: (sessionStart: TimeInterval, fileStart: TimeInterval)?

    /// The source started recording. `fileDuration` is how much audio its file already holds — what
    /// was actually written rather than an elapsed-time estimate, so placements cannot drift from it.
    mutating func sourceStarted(atSessionTime sessionStart: TimeInterval, fileDuration: TimeInterval) {
        guard open == nil else { return }
        open = (max(0, sessionStart), max(0, fileDuration))
    }

    /// The source stopped. Closes the open activation at the file's current length.
    mutating func sourceStopped(fileDuration: TimeInterval) {
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
        copy.sourceStopped(fileDuration: fileDuration)
        return copy.placements
    }

    /// Whether the file can stand in for the session timeline as it is.
    ///
    /// True only when the source ran once, from the start of the meeting: then the file *is* the
    /// timeline and can be saved untouched. Anything else — a late join, a mute — means the file is
    /// shorter than the meeting and has to be laid out before it represents it.
    static func fileMatchesSessionTimeline(_ placements: [Placement]) -> Bool {
        guard let only = placements.first, placements.count == 1 else { return false }
        return only.sessionStart <= 0.001 && only.fileStart <= 0.001
    }
}
