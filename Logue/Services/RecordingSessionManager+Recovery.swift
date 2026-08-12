import Foundation

/// Rebuilding a session the app never got to finish.
///
/// A recording writes its audio continuously but resolves *where that audio belongs* only when it
/// stops, and holds its transcript in memory until then. A checkpoint is what bridges that: with it,
/// an interrupted session is a meeting missing its last few seconds; without it, it is two audio
/// files of unknown offset and no text.
///
/// Recovery is silent by design. It restores the meeting and says so on the meeting itself — it does
/// not ask, because there is no decision the user could usefully make about it at launch.
extension RecordingSessionManager {
    /// Rebuilds every session left behind by an unclean exit. Safe to call at launch; does nothing
    /// while a recording is running.
    func recoverInterruptedSessions() async {
        guard recordingState == .idle else { return }

        for meetingID in InProgressRecordingStore.pendingMeetingIDs() {
            guard recordingState == .idle else { return }
            await recoverSession(meetingID)
        }
    }

    private func recoverSession(_ meetingID: UUID) async {
        guard let checkpoint = RecordingCheckpoint.read(meetingID: meetingID) else {
            // A working directory with no checkpoint is a session that crashed inside its first
            // thirty seconds. There is nothing to rebuild from, so it is cleared rather than kept.
            logger.info("Discarding an interrupted session with no checkpoint")
            InProgressRecordingStore.clear(meetingID: meetingID)
            return
        }

        guard MeetingStore.shared.meetings.contains(where: { $0.id == meetingID }) else {
            logger.info("Interrupted session belongs to a meeting that no longer exists — discarding")
            InProgressRecordingStore.clear(meetingID: meetingID)
            return
        }

        logger.info("Recovering an interrupted recording covering \(Int(checkpoint.coveredDuration))s")

        MeetingStore.shared.restoreRecoveredSession(
            for: meetingID,
            segments: checkpoint.segments,
            duration: checkpoint.timeOffset + checkpoint.coveredDuration
        )

        let savedAudio = await persistRecordingAudio(
            sources: captureSources(from: checkpoint),
            meetingID: meetingID
        )

        await reprocessRecoveredAudio(
            savedAudio,
            checkpoint: checkpoint,
            meetingID: meetingID
        )

        InProgressRecordingStore.clear(meetingID: meetingID)
        postRecordingPipeline.start(for: meetingID)
        MeetingStore.shared.saveMeeting(id: meetingID)
        logger.info("Recovered meeting \(meetingID)")
    }

    /// Rebuilds the capture sources from what the checkpoint wrote down.
    ///
    /// The placements are the part that matters. They are what says where each stretch of each file
    /// belongs on the meeting, and they cannot be worked out afterwards from the files themselves.
    private func captureSources(from checkpoint: RecordingCheckpoint) -> CaptureSources {
        var sources = CaptureSources()
        guard let directory = try? InProgressRecordingStore.directory(for: checkpoint.meetingID) else {
            return sources
        }

        if let name = checkpoint.micFileName {
            let url = directory.appending(component: name)
            if FileManager.default.fileExists(atPath: url.path) {
                sources.micURL = url
                sources.micPlacements = checkpoint.micPlacements
            }
        }
        if let name = checkpoint.systemFileName {
            let url = directory.appending(component: name)
            if FileManager.default.fileExists(atPath: url.path) {
                sources.systemURL = url
                sources.systemPlacements = checkpoint.systemPlacements
            }
        }
        return sources
    }

    /// Runs the batch transcription and diarization pass over recovered audio.
    ///
    /// The recovered file is read from disk rather than from a live session's buffer, because there
    /// is no live session — this is the same route a recording too long for memory takes.
    private func reprocessRecoveredAudio(
        _ savedAudio: SavedRecording,
        checkpoint: RecordingCheckpoint,
        meetingID: UUID
    ) async {
        guard savedAudio.describesSessionTimeline,
              let audioURL = savedAudio.url,
              FileManager.default.fileExists(atPath: audioURL.path)
        else {
            logger.info("Recovered audio is not the session timeline — keeping the checkpointed transcript")
            return
        }

        let diarizer = DiarizationManager()
        do {
            try await diarizer.initialize()
        } catch {
            logger.warning("Recovery diarization unavailable: \(error.localizedDescription, privacy: .public)")
            return
        }

        isDiarizing = true
        diarizationStage = "Recovering meeting…"
        defer {
            isDiarizing = false
            diarizationStage = ""
        }

        guard let result = await diarizer.processRecordingFile(audioURL) else {
            logger.warning("Recovery pass produced nothing — the checkpointed transcript stands")
            return
        }

        // Bounded by what the recovered audio actually holds. A recovery that heard less than the
        // meeting must not delete transcript past its end.
        if !result.segments.isEmpty {
            MeetingStore.shared.replaceTranscript(
                for: meetingID,
                with: result.segments,
                sessionStart: checkpoint.timeOffset,
                heardDuration: checkpoint.coveredDuration
            )
        }

        guard !result.speakers.isEmpty else { return }
        applySortformerUpdates(
            SortformerTimeline.normalize(result.speakers),
            for: meetingID,
            sessionStart: checkpoint.timeOffset
        )
        renumberSpeakers(for: meetingID)
        alignRecoveredTranscript(for: meetingID)
    }

    private func alignRecoveredTranscript(for meetingID: UUID) {
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }),
              !meeting.speakerSegments.isEmpty
        else { return }

        var speakerSegments = meeting.speakerSegments
        alignTranscriptionWithSpeakers(
            transcriptSegments: meeting.segments,
            speakerSegments: &speakerSegments,
            totalDuration: meeting.duration
        )
        store.updateSpeakerData(
            for: meetingID,
            speakers: meeting.speakers,
            speakerSegments: speakerSegments
        )
    }
}
