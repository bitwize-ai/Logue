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

        // The store loads from disk asynchronously, and this runs on the same actor — so without
        // waiting it observes an empty library, concludes every interrupted meeting no longer
        // exists, and deletes the audio it exists to rebuild.
        guard await waitForMeetingStore() else {
            logger.warning("Meeting store did not finish loading — leaving interrupted sessions untouched")
            return
        }

        let pending = InProgressRecordingStore.pendingMeetingIDs()
        guard !pending.isEmpty else { return }

        // Held for the duration. Recovery reaches into the same audio recorder and working
        // directories a live session uses, and its composition step is slow enough that a user can
        // easily press record inside it.
        guard recordingState == .idle else { return }
        recordingState = .recovering
        defer { recordingState = .idle }

        for meetingID in pending {
            await recoverSession(meetingID)
        }
    }

    /// Waits for the meeting library to finish loading, giving up rather than waiting forever.
    ///
    /// Returning false means we do not know what the library holds, and nothing may be deleted on
    /// the strength of a meeting appearing to be absent.
    private func waitForMeetingStore() async -> Bool {
        let deadline = ContinuousClock.now + AppConstants.Delays.meetingStoreLoadTimeout
        while ContinuousClock.now < deadline {
            if MeetingStore.shared.isLoaded {
                return true
            }
            // Not `try?`. The one thing `Task.sleep` throws is cancellation, and swallowing it
            // here leaves a loop with no suspension left in its body: `.task` on the root view
            // cancels this when the window closes during launch, and it then span the main actor
            // flat out for the rest of the 30-second budget — a beachball exactly when the
            // store is slow, which is when this code runs at all.
            do {
                try await Task.sleep(for: AppConstants.Delays.meetingStoreLoadPoll)
            } catch {
                return false
            }
        }
        return MeetingStore.shared.isLoaded
    }

    private func recoverSession(_ meetingID: UUID) async {
        let checkpoint: RecordingCheckpoint
        switch RecordingCheckpoint.read(meetingID: meetingID) {
        case let .checkpoint(read):
            checkpoint = read
        case .absent:
            // A working directory with no checkpoint is a session that crashed inside its first
            // thirty seconds. There is nothing to rebuild from, so it is cleared rather than kept.
            logger.info("Discarding an interrupted session with no checkpoint")
            InProgressRecordingStore.clear(meetingID: meetingID)
            return
        case .unreadable:
            // A checkpoint that exists but will not decrypt says nothing about the audio beside
            // it. Kept, so a restored-from-backup Mac does not destroy the recording it was
            // meant to rebuild.
            logger.error("Checkpoint could not be read — keeping the interrupted recording")
            return
        }

        guard MeetingStore.shared.meetings.contains(where: { $0.id == meetingID }) else {
            // `isLoaded` on its own is not evidence the library was read. `loadFromDiskAsync`
            // sets it on all four terminal paths, two of which are failures: every meeting file
            // failing to decrypt leaves `meetings` empty, and a decode error substitutes seed
            // data. Either would make a real meeting look deleted — and this branch removes the
            // recording's audio, which is the outcome `waitForMeetingStore` exists to prevent.
            // So all three have to hold: loading finished, it did not fall back to seed data,
            // and it actually produced meetings.
            let store = MeetingStore.shared
            guard store.isLoaded, !store.loadedSeedData, !store.meetings.isEmpty else {
                logger.warning(
                    "Meeting not found but the library did not load cleanly — keeping the recording"
                )
                return
            }
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
        let directory: URL
        do {
            directory = try InProgressRecordingStore.directory(for: checkpoint.meetingID)
        } catch {
            // Silently returning empty sources here loses the recording and says nothing: the
            // audio never gets attached, the batch pass declines, and the meeting comes back
            // with only its checkpointed transcript. `SandboxContainerMigrator` moving the
            // container is exactly the case recovery exists to tolerate, and exactly the case
            // that makes this throw.
            logger.error(
                "Recovery could not reach its working directory: \(error.localizedDescription, privacy: .public)"
            )
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

        diarizingMeetingID = meetingID
        diarizationStage = "Recovering meeting…"
        defer {
            diarizingMeetingID = nil
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
