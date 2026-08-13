import Foundation

/// Replacing a meeting's transcript after the fact.
///
/// Both of these hand back lines the meeting already had — realigned text after the post-recording
/// pass, or the transcript a checkpoint held when the app stopped. Neither invents new segments, so
/// nothing the reader is looking at moves.
extension MeetingStore {
    /// Replaces a meeting's transcript with the same lines carrying better text.
    ///
    /// Used by the post-recording pass after realignment: the segments handed in are the meeting's
    /// own, with their identities, starts, ends and speakers intact, so nothing the reader is
    /// looking at moves.
    func updateSegments(_ segments: [TranscriptSegment], for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].segments = segments
        saveMeeting(id: meetingID)
    }

    /// Puts back what a session held in memory when the app stopped.
    ///
    /// The checkpointed segments replace whatever is on the meeting rather than appending to it: a
    /// checkpoint is a snapshot of the whole session's transcript, so appending would duplicate
    /// every line that had already been saved.
    func restoreRecoveredSession(for meetingID: UUID, segments: [TranscriptSegment], duration: TimeInterval) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].segments = segments
        meetings[index].duration = max(meetings[index].duration, duration)
        meetings[index].wasRecovered = true
        saveMeeting(id: meetingID)
    }
}
