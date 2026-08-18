import Foundation

/// Writing down where a recording has got to, so an interrupted one can be rebuilt.
///
/// Split out from `RecordingSessionManager` to keep the core inside the type-length limit; the state
/// it reaches for is marked `// Extension-visible: +Checkpoint` there.
extension RecordingSessionManager {
    // MARK: - Checkpointing

    /// Writes down where the session has got to, every thirty seconds.
    func startCheckpointing() {
        checkpointTask?.cancel()
        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppConstants.Delays.recordingCheckpointInterval)
                guard !Task.isCancelled, let self else { return }
                writeCheckpoint()
            }
        }
    }

    func writeCheckpoint() {
        guard isRecording, !isStopping,
              let meetingID = currentMeetingID,
              let sessionStart = sessionStartDate,
              let meeting = MeetingStore.shared.meetings.first(where: { $0.id == meetingID })
        else { return }

        let checkpoint = RecordingCheckpoint(
            meetingID: meetingID,
            sessionStart: sessionStart,
            timeOffset: timeOffset,
            segments: meeting.segments,
            // `finalized` rather than `placements`: it closes the activation that is still open,
            // which is precisely the one a crash would otherwise lose entirely.
            micPlacements: micSegments.finalized(fileDuration: audioRecorder.recordedDuration),
            systemPlacements: systemSegments.finalized(fileDuration: systemRecordedDuration),
            micFileName: audioRecorder.tempFileURL?.lastPathComponent,
            systemFileName: systemAudioTempURL?.lastPathComponent,
            writtenAt: Date()
        )

        do {
            try RecordingCheckpoint.write(checkpoint)
        } catch {
            logger.error("Checkpoint write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
