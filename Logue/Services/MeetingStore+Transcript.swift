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
    /// The checkpoint and the saved transcript are merged by id, never one assigned over the
    /// other. A checkpoint is a snapshot of the whole session, so a blind append would duplicate
    /// every line already saved — and a blind replace would delete the lines saved *since* the
    /// last checkpoint, which is the more common case. See the body for which one wins.
    func restoreRecoveredSession(for meetingID: UUID, segments: [TranscriptSegment], duration: TimeInterval) {
        guard let index = meetingIndex(for: meetingID) else { return }

        // The transcript is persisted every few seconds while recording, but checkpointed only
        // every thirty — so after a crash the meeting on disk usually holds *more* lines than the
        // checkpoint does. Assigning the checkpoint wholesale would delete correct, already-durable
        // transcript, which is the opposite of what recovery is for. Whichever set reaches further
        // wins, and lines present in both keep the saved copy.
        let saved = meetings[index].segments
        let savedReach = saved.map(\.endTime).max() ?? 0
        let checkpointReach = segments.map(\.endTime).max() ?? 0

        if checkpointReach > savedReach {
            var merged = saved
            let known = Set(saved.map(\.id))
            merged.append(contentsOf: segments.filter { !known.contains($0.id) })
            meetings[index].segments = merged.sorted { $0.startTime < $1.startTime }
        }
        meetings[index].duration = max(meetings[index].duration, duration)
        meetings[index].wasRecovered = true
        saveMeeting(id: meetingID)
    }
}
