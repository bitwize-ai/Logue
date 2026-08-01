import Foundation

/// Decides how much of a recording session's transcript the post-recording batch ASR pass is
/// allowed to replace.
///
/// Batch ASR (Parakeet TDT) re-transcribes the session in one pass over the accumulated 16 kHz
/// buffer and is more accurate than the live stream, so its output replaces the streaming draft.
/// But the in-memory buffer is bounded by what the machine can hold (see `AudioTimelineMixer`), and
/// once it is full the rest of the meeting's audio is dropped. Handing the whole
/// session over to a batch result that only heard the first part of it is how a two-hour meeting
/// ended up with a transcript that stopped dead at the cap — the live transcriber had heard all of
/// it, and the replacement threw that away.
///
/// So the batch result only replaces the stretch of timeline it actually heard. Whatever the live
/// transcriber produced past that point stays: streaming quality beats no transcript at all.
enum TranscriptReplacement {
    /// - Parameters:
    ///   - existing: the meeting's current segments, on the meeting timeline.
    ///   - batch: batch ASR output, timed from the start of this session's own audio.
    ///   - sessionStart: where this session begins on the meeting timeline. Anything earlier belongs
    ///     to a previous recording session and is never touched.
    ///   - heardDuration: how many seconds of this session's audio the batch pass actually received,
    ///     or `nil` when it received all of it. A segment straddling that boundary is dropped in
    ///     favour of the batch text rather than kept alongside it, so no sentence appears twice.
    static func merged(
        existing: [TranscriptSegment],
        batch: [TranscriptSegment],
        sessionStart: TimeInterval,
        heardDuration: TimeInterval?
    ) -> [TranscriptSegment] {
        let shifted = batch.map { segment -> TranscriptSegment in
            var moved = segment
            moved.startTime += sessionStart
            moved.endTime += sessionStart
            return moved
        }

        var kept = existing.filter { $0.startTime < sessionStart }

        if let heardDuration {
            let coverageEnd = sessionStart + heardDuration
            kept += existing.filter { $0.startTime >= coverageEnd }
        }

        return (kept + shifted).sorted { $0.startTime < $1.startTime }
    }
}
