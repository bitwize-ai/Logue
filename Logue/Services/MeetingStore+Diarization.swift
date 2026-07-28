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
    func replaceTranscript(
        for meetingID: UUID,
        with segments: [TranscriptSegment],
        sessionStart: TimeInterval = 0
    ) {
        guard let index = meetingIndex(for: meetingID) else { return }

        let shifted = segments.map { segment in
            var moved = segment
            moved.startTime += sessionStart
            moved.endTime += sessionStart
            return moved
        }
        let earlierSessions = meetings[index].segments.filter { $0.startTime < sessionStart }

        meetings[index].segments = (earlierSessions + shifted).sorted { $0.startTime < $1.startTime }
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}
