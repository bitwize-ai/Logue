import Foundation

// MARK: - Speaker Diarization

extension MeetingStore {
    /// Persists diarization output and attributes transcript segments to speakers.
    ///
    /// Labelling is delegated to `SpeakerAlignment`, which decides by time overlap and may split a
    /// transcript segment that spans two speakers. Segments already carrying a label are left alone,
    /// preserving "You" attribution and any correction the user made by hand.
    func updateSpeakerData(for meetingID: UUID, speakers: [Speaker], speakerSegments: [SpeakerSegment]) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].speakers = speakers
        meetings[index].speakerSegments = speakerSegments
        meetings[index].hasSpeakerData = !speakerSegments.isEmpty

        meetings[index].segments = SpeakerAlignment.align(
            segments: meetings[index].segments,
            speakerSegments: speakerSegments,
            speakerNamesByID: Dictionary(
                speakers.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
        )

        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    /// Replace this recording session's transcript segments with the output of batch ASR
    /// (Parakeet TDT). Called after recording stops to upgrade streaming transcript quality.
    ///
    /// `sessionStart` is the meeting timeline offset the session began at. Batch ASR timings are
    /// relative to the session's own audio buffer, so they are shifted onto the meeting timeline and
    /// only segments from this session are replaced — otherwise resuming a recording would discard
    /// every earlier session's transcript.
    ///
    /// Required deliberately: a default of `0` would filter for segments starting below zero, find
    /// none, and silently go back to replacing the whole array — the exact data loss this argument
    /// exists to prevent, in the one scenario least likely to be exercised while developing.
    ///
    /// `heardDuration` bounds it the other way. Batch ASR runs on a memory-capped audio buffer, so
    /// on a long recording it hears only the start of the session; pass how much it heard and the
    /// live transcript for the rest is kept rather than replaced by silence. `nil` means it heard
    /// the whole session. `TranscriptReplacement` holds the rule.
    func replaceTranscript(
        for meetingID: UUID,
        with segments: [TranscriptSegment],
        sessionStart: TimeInterval,
        heardDuration: TimeInterval?
    ) {
        guard let index = meetingIndex(for: meetingID) else { return }

        meetings[index].segments = TranscriptReplacement.merged(
            existing: meetings[index].segments,
            batch: segments,
            sessionStart: sessionStart,
            heardDuration: heardDuration
        )
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}
