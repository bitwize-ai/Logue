import FluidAudio
import Foundation
import os.log

/// Diarization-related methods extracted from RecordingSessionManager.
/// Handles speaker detection, merging, alignment, and Sortformer streaming updates.
extension RecordingSessionManager {
    // MARK: - Model Initialization

    /// Waits for diarization model initialization, capped at
    /// `AppConstants.Delays.diarizationInitStopWait`.
    ///
    /// Without this wait, stopping while models are still downloading leaves Sortformer not
    /// streaming, and diarization silently degrades to the less accurate batch path. The cap keeps a
    /// slow first-run download from holding up post-recording AI indefinitely.
    func awaitDiarizationInit(_ initTask: Task<Void, Never>) async {
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await initTask.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: AppConstants.Delays.diarizationInitStopWait)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if !finished {
            logger.warning("Diarization model init still running at stop — proceeding without waiting further")
        }
    }

    // MARK: - Post-Recording Diarization Pipeline

    /// Runs the full diarization pipeline after recording stops.
    /// Uses Sortformer's `processComplete()` for maximum accuracy — the model sees the entire conversation.
    /// Falls back to batch DiarizerManager if Sortformer is unavailable.
    ///
    /// - Parameter sessionStart: Where this recording session begins on the meeting timeline. Both
    ///   diarizers time their output from the start of the session's own audio buffer, so their
    ///   timestamps need shifting by this much when a recording resumes into an existing meeting.
    /// - Parameter sessionDuration: How long this recording session ran. The disk route checks the
    ///   saved audio against it before trusting the file's timings.
    func processDiarization(
        for meetingID: UUID,
        diarizer: DiarizationManager,
        sessionStart: TimeInterval,
        sessionDuration: TimeInterval
    ) async {
        isDiarizing = true
        diarizationStage = "Identifying speakers…"

        // Primary path: Sortformer processComplete on full audio buffer
        if await processSortformerDiarization(
            for: meetingID,
            diarizer: diarizer,
            sessionStart: sessionStart,
            sessionDuration: sessionDuration
        ) {
            return
        }

        // Fallback: batch DiarizerManager
        diarizationStage = "Identifying speakers…"
        logger.info("Starting batch post-recording diarization for meeting \(meetingID)...")

        guard let result = await diarizer.finishProcessing() else {
            logger.warning("Post-recording diarization returned no result (empty audio or not initialized)")
            isDiarizing = false
            diarizationStage = ""
            return
        }
        logger.info("Post-recording diarization got \(result.segments.count) segments")

        // Map FluidAudio results into our Speaker + SpeakerSegment models
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else {
            isDiarizing = false
            return
        }

        var (speakers, speakerSegments) = mergeDiarizationResult(
            result,
            into: meeting,
            sessionStart: sessionStart
        )

        diarizationStage = "Aligning transcript…"

        // Align transcription text with speaker segments
        alignTranscriptionWithSpeakers(
            transcriptSegments: meeting.segments,
            speakerSegments: &speakerSegments,
            totalDuration: meeting.duration
        )

        store.updateSpeakerData(
            for: meetingID,
            speakers: speakers,
            speakerSegments: speakerSegments
        )

        // Auto-merge duplicate speakers detected by FluidAudio's SpeakerManager
        await autoMergeSpeakers(for: meetingID, diarizer: diarizer)

        isDiarizing = false
        diarizationStage = ""
        logger.info("Diarization complete: \(speakers.count) speakers, \(speakerSegments.count) segments")
    }

    /// What the post-recording pass produced, and how much of the session it can speak for.
    private struct BatchPassResult {
        var segments: [TranscriptSegment]?
        var speakers: [SortformerSpeakerUpdate]?
        /// Seconds of the session the pass actually heard, or `nil` when it heard all of it.
        var heardDuration: TimeInterval?
    }

    /// Runs Parakeet TDT and Sortformer over the session, from memory when the recording fits and
    /// from its own file on disk when it does not.
    ///
    /// The in-memory timeline is bounded by what the machine can hold, and a long meeting overruns
    /// it. That used to be the end of the story — speakers and batch-quality transcript simply
    /// stopped there. But the recording is already on disk for playback, and neither model needs it
    /// in one piece, so an overrun becomes a change of route rather than a loss.
    ///
    /// The disk route is only taken when the saved file is long enough to *be* this session, checked
    /// against `sessionDuration`. A file that falls short is a file whose timestamps do not describe
    /// the meeting, and stamping its results over a correctly-timed live transcript would be worse
    /// than keeping the live one.
    private func runBatchPass(
        for meetingID: UUID,
        diarizer: DiarizationManager,
        sessionDuration: TimeInterval
    ) async -> BatchPassResult {
        guard diarizer.heardDuration != nil else {
            // The whole session fitted in memory: the usual pass, on the buffer.
            return await inMemoryPass(diarizer: diarizer, heardDuration: nil)
        }

        guard let audioURL = trustworthyRecordingFile(for: meetingID, sessionDuration: sessionDuration) else {
            return await inMemoryPass(diarizer: diarizer, heardDuration: diarizer.heardDuration)
        }

        logger.info("Recording outgrew the in-memory timeline — processing it from disk instead")
        diarizationStage = "Processing long recording…"
        // Deliberately before the disk pass and before the buffer is taken: the file is the whole
        // session, and holding half a gigabyte of now-redundant audio while two models run is how
        // a long recording runs the machine out of memory at the last moment.
        diarizer.discardAudioBuffer()

        guard let result = await diarizer.processRecordingFile(audioURL) else {
            logger.warning("Long-recording pass failed — the buffer is gone, so this session keeps its live transcript")
            return BatchPassResult(segments: nil, speakers: nil, heardDuration: 0)
        }

        // Either model can come back empty on its own. Whichever one worked still speaks for the
        // whole session, rather than both being thrown away together.
        if result.segments.isEmpty {
            logger.warning("Long-recording transcription produced nothing — keeping the live transcript")
        }
        if result.speakers.isEmpty {
            logger.warning("Long-recording diarization produced nothing — the transcript stands without speaker labels")
        }
        return BatchPassResult(
            segments: result.segments.isEmpty ? nil : result.segments,
            speakers: result.speakers.isEmpty ? nil : result.speakers,
            // A transcript covering the whole session may replace all of it; with no transcript there
            // is nothing to replace, and zero keeps every live segment.
            heardDuration: result.segments.isEmpty ? 0 : nil
        )
    }

    /// The usual pass, over the audio held in memory.
    private func inMemoryPass(
        diarizer: DiarizationManager,
        heardDuration: TimeInterval?
    ) async -> BatchPassResult {
        if let heardDuration {
            logger.warning(
                """
                Audio buffer capped with no file to fall back on: heard \(String(format: "%.0f", heardDuration), privacy: .public)s \
                of this session — keeping the live transcript beyond that point
                """
            )
        }
        let audioBuffer = diarizer.takeAudioBuffer()
        // Both models are independent and take ~30-60s each on a 1-hour recording — run them together.
        async let sortformerTask = diarizer.processCompleteWith(audioBuffer)
        async let asrTask = diarizer.transcribeBuffer(audioBuffer)
        let (speakers, segments) = await (sortformerTask, asrTask)
        return BatchPassResult(segments: segments, speakers: speakers, heardDuration: heardDuration)
    }

    /// The meeting's saved audio, but only if it is long enough to stand for this whole session.
    ///
    /// Everything the disk route concludes is timed from the start of this file, so a file that is
    /// materially shorter than the session did not record all of it — a source muted for part of the
    /// meeting, a composition that fell back to a raw capture, a stale file from an earlier session.
    /// The results would be stamped at the wrong times over a live transcript that had them right.
    private func trustworthyRecordingFile(
        for meetingID: UUID,
        sessionDuration: TimeInterval
    ) -> URL? {
        guard let url = MeetingStore.shared.meetings.first(where: { $0.id == meetingID })?.audioFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else {
            logger.warning("Recording outgrew memory but no saved audio file was found")
            return nil
        }
        guard sessionDuration > 0 else { return url }

        let fileDuration = AudioFileChunkReader.duration(of: url) ?? 0
        let shortfall = sessionDuration - fileDuration
        guard shortfall <= AppConstants.Diarization.recordingFileDurationTolerance else {
            logger.warning(
                """
                Saved audio is \(String(format: "%.0f", shortfall), privacy: .public)s shorter than the \
                session — its timings cannot describe this meeting, so the live transcript is kept
                """
            )
            return nil
        }
        return url
    }

    /// Primary diarization path: transcribes and diarizes the session, then aligns the transcript
    /// with the speaker segments.
    /// Returns `true` when it handled diarization (streaming was active); `false` to fall back to batch.
    private func processSortformerDiarization(
        for meetingID: UUID,
        diarizer: DiarizationManager,
        sessionStart: TimeInterval,
        sessionDuration: TimeInterval
    ) async -> Bool {
        guard diarizer.isStreamingActive else { return false }
        logger.info("Starting parallel Sortformer + batch ASR for meeting \(meetingID)...")

        let pass = await runBatchPass(for: meetingID, diarizer: diarizer, sessionDuration: sessionDuration)
        let heardDuration = pass.heardDuration
        let sortformerUpdates = pass.speakers
        let batchSegments = pass.segments

        // Replace this session's streaming transcript with the accurate Parakeet TDT result before
        // speakers are assigned, so alignment runs against the final text rather than the draft.
        if let batchSegments {
            MeetingStore.shared.replaceTranscript(
                for: meetingID,
                with: batchSegments,
                sessionStart: sessionStart,
                heardDuration: heardDuration
            )
            logger.info("Streaming transcript replaced with batch ASR (\(batchSegments.count) segments)")
        }

        if let updates = sortformerUpdates {
            // Raw Sortformer output is fragmented — sub-second slivers, split turns, and rapid
            // alternations that would make speaker labels flip mid-sentence.
            let normalized = SortformerTimeline.normalize(updates)
            logger.info("Sortformer timeline: \(updates.count) raw segments → \(normalized.count) normalized")
            applySortformerUpdates(normalized, for: meetingID, sessionStart: sessionStart)
            // Renumber auto-named speakers sequentially (1, 2, 3…). Sortformer's internal cluster
            // indices are not contiguous (e.g. Speaker 2, Speaker 4 for a 2-speaker meeting).
            renumberSpeakers(for: meetingID)
        }

        diarizationStage = "Aligning transcript…"

        // Align transcript text with speaker segments
        let store = MeetingStore.shared
        if let meeting = store.meetings.first(where: { $0.id == meetingID }),
           !meeting.speakerSegments.isEmpty
        {
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

        isDiarizing = false
        diarizationStage = ""
        logger.info("Sortformer post-recording diarization complete for meeting \(meetingID)")
        return true
    }

    // MARK: - Speaker Auto-Merge

    /// Auto-merge duplicate speakers using FluidAudio's SpeakerManager similarity detection.
    func autoMergeSpeakers(for meetingID: UUID, diarizer: DiarizationManager) async {
        guard let fluidDiarizer = diarizer.fluidDiarizerForMerge else { return }
        let mergeablePairs = await fluidDiarizer.speakerManager.findMergeablePairs()
        guard !mergeablePairs.isEmpty else { return }

        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else { return }

        var speakers = meeting.speakers
        var speakerSegments = meeting.speakerSegments

        for pair in mergeablePairs {
            await fluidDiarizer.speakerManager.mergeSpeaker(pair.speakerToMerge, into: pair.destination)

            for i in speakerSegments.indices where speakerSegments[i].speakerId == pair.speakerToMerge {
                speakerSegments[i] = SpeakerSegment(
                    speakerId: pair.destination,
                    startTime: speakerSegments[i].startTime,
                    endTime: speakerSegments[i].endTime,
                    confidence: speakerSegments[i].confidence,
                    embedding: speakerSegments[i].embedding
                )
            }

            speakers.removeAll { $0.id == pair.speakerToMerge }
        }

        // Re-number speaker names
        for i in speakers.indices where speakers[i].name.hasPrefix("Speaker ") {
            speakers[i] = Speaker(
                id: speakers[i].id,
                name: "Speaker \(i + 1)",
                color: Speaker.generateColor(for: i),
                embedding: speakers[i].embedding
            )
        }

        store.updateSpeakerData(for: meetingID, speakers: speakers, speakerSegments: speakerSegments)
        logger.info("Auto-merged \(mergeablePairs.count) duplicate speaker pair(s)")
    }

    // MARK: - Speaker Renumbering

    /// Removes auto-named speakers with no transcript segments, then renumbers the rest as
    /// Speaker 1, Speaker 2, … in chronological first-appearance order.
    /// Fixes gaps from Sortformer's raw cluster indices (e.g. Speaker 2 + Speaker 4 → 1 + 2).
    /// All changes are written in a single updateMeeting() call to avoid double-write races.
    func renumberSpeakers(for meetingID: UUID) {
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else { return }

        // Auto-named speakers in the order they first appear in the transcript
        var seen = Set<String>()
        var orderedLabels: [String] = []
        for seg in meeting.segments.sorted(by: { $0.startTime < $1.startTime }) {
            guard let label = seg.speakerLabel, label.hasPrefix("Speaker ") else { continue }
            if seen.insert(label).inserted {
                orderedLabels.append(label)
            }
        }

        guard !orderedLabels.isEmpty else { return }

        // Map old label → sequential label ("Speaker 3" → "Speaker 1", etc.)
        var labelRemap: [String: String] = [:]
        for (idx, oldLabel) in orderedLabels.enumerated() {
            let newLabel = "Speaker \(idx + 1)"
            if oldLabel != newLabel {
                labelRemap[oldLabel] = newLabel
            }
        }

        let activeLabels = Set(meeting.segments.compactMap(\.speakerLabel))
        let hasUnused = meeting.speakers.contains {
            $0.name.hasPrefix("Speaker ") && !activeLabels.contains($0.name)
        }

        guard !labelRemap.isEmpty || hasUnused else { return }

        var updated = meeting

        // 1. Rebuild speakers list: auto-named ones renumbered in order of first appearance,
        //    non-auto-named ones (e.g. "You", manually renamed) preserved at the end.
        var newSpeakers: [Speaker] = []
        for (seqIdx, oldLabel) in orderedLabels.enumerated() {
            guard let speaker = meeting.speakers.first(where: { $0.name == oldLabel }) else { continue }
            newSpeakers.append(Speaker(
                id: speaker.id,
                name: "Speaker \(seqIdx + 1)",
                color: Speaker.generateColor(for: seqIdx),
                embedding: speaker.embedding
            ))
        }
        for speaker in meeting.speakers where !speaker.name.hasPrefix("Speaker ") {
            newSpeakers.append(speaker)
        }
        updated.speakers = newSpeakers

        // 2. Remap segment labels to match new speaker names
        for i in updated.segments.indices {
            if let old = updated.segments[i].speakerLabel, let newName = labelRemap[old] {
                updated.segments[i].speakerLabel = newName
            }
        }

        // Single write — avoids updateSpeakerData + updateMeeting double-write race
        store.updateMeeting(updated)
        logger.info(
            "Renumbered speakers: \(labelRemap, privacy: .public), removed \(meeting.speakers.count - newSpeakers.count) unused"
        )
    }

    // MARK: - Result Merging

    /// Merges diarization result segments into existing speaker data for a meeting.
    /// Segment times are shifted by `sessionStart` onto the meeting timeline.
    func mergeDiarizationResult(
        _ result: DiarizationResult,
        into meeting: MeetingNote,
        sessionStart: TimeInterval
    ) -> (speakers: [Speaker], speakerSegments: [SpeakerSegment]) {
        var speakers = meeting.speakers
        var speakerSegments = meeting.speakerSegments
        var seenSpeakerIDs = Set(speakers.map(\.id))

        for segment in result.segments {
            if !seenSpeakerIDs.contains(segment.speakerId) {
                seenSpeakerIDs.insert(segment.speakerId)
                let speakerIndex = speakers.count
                speakers.append(Speaker(
                    id: segment.speakerId,
                    name: "Speaker \(speakerIndex + 1)",
                    color: Speaker.generateColor(for: speakerIndex),
                    embedding: segment.embedding
                ))
            }

            speakerSegments.append(SpeakerSegment(
                speakerId: segment.speakerId,
                startTime: TimeInterval(segment.startTimeSeconds) + sessionStart,
                endTime: TimeInterval(segment.endTimeSeconds) + sessionStart,
                confidence: segment.qualityScore,
                embedding: segment.embedding
            ))
        }
        return (speakers, speakerSegments)
    }

    // MARK: - Sortformer Updates

    /// Applies Sortformer speaker segments to the meeting. Runs once, after recording stops —
    /// segment times are shifted by `sessionStart` onto the meeting timeline.
    func applySortformerUpdates(
        _ updates: [SortformerSpeakerUpdate],
        for meetingID: UUID,
        sessionStart: TimeInterval
    ) {
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else { return }

        var speakers = meeting.speakers
        var speakerSegments = meeting.speakerSegments
        var seenSpeakerIDs = Set(speakers.map(\.id))

        for update in updates {
            let speakerID = "sortformer_speaker_\(update.speakerIndex)"

            if !seenSpeakerIDs.contains(speakerID) {
                seenSpeakerIDs.insert(speakerID)
                // Use speakers.count (sequential order of appearance) so names are
                // always "Speaker 1", "Speaker 2" … regardless of Sortformer's internal cluster index.
                let sequentialIndex = speakers.count
                let speaker = Speaker(
                    id: speakerID,
                    name: "Speaker \(sequentialIndex + 1)",
                    color: Speaker.generateColor(for: sequentialIndex)
                )
                speakers.append(speaker)
            }

            let startTime = update.startTime + sessionStart
            let endTime = update.endTime + sessionStart

            // Deduplicate: skip if overlapping with an existing segment for the same speaker
            let isDuplicate = speakerSegments.suffix(20).contains { existing in
                existing.speakerId == speakerID
                    && abs(existing.startTime - startTime) < AppConstants.Diarization.segmentDedupTolerance
            }
            guard !isDuplicate else { continue }

            let speakerSeg = SpeakerSegment(
                speakerId: speakerID,
                startTime: startTime,
                endTime: endTime,
                confidence: 1.0
            )
            speakerSegments.append(speakerSeg)
        }

        store.updateSpeakerData(
            for: meetingID,
            speakers: speakers,
            speakerSegments: speakerSegments
        )
    }

    // MARK: - Text Alignment

    /// Align transcript text with speaker segments using time-overlap mapping.
    /// For each speaker segment, collects text from transcript segments whose midpoint
    /// falls within the speaker segment's time range. Respects word boundaries.
    func alignTranscriptionWithSpeakers(
        transcriptSegments: [TranscriptSegment],
        speakerSegments: inout [SpeakerSegment],
        totalDuration: TimeInterval
    ) {
        guard !transcriptSegments.isEmpty, !speakerSegments.isEmpty else { return }

        let sortedTranscripts = transcriptSegments.sorted { $0.startTime < $1.startTime }
        let tolerance = AppConstants.Diarization.speakerLabelTolerance

        // Sort indices so the two-pointer scan advances monotonically (O(N+M) not O(N*M)).
        let sortedIndices = speakerSegments.indices.sorted {
            speakerSegments[$0].startTime < speakerSegments[$1].startTime
        }

        var transcriptStart = 0

        for idx in sortedIndices {
            let segStart = speakerSegments[idx].startTime
            let segEnd = speakerSegments[idx].endTime
            guard segEnd > segStart else { continue }

            // Advance the lower pointer past transcripts that cannot belong to this or any later segment.
            while transcriptStart < sortedTranscripts.count,
                  sortedTranscripts[transcriptStart].endTime < segStart - tolerance
            {
                transcriptStart += 1
            }

            var texts: [String] = []
            var i = transcriptStart
            while i < sortedTranscripts.count {
                let transcript = sortedTranscripts[i]
                if transcript.startTime > segEnd + tolerance {
                    break
                }
                let midpoint = (transcript.startTime + transcript.endTime) / 2
                // Half-open interval [segStart, segEnd) ensures each transcript is assigned
                // to exactly one speaker when its midpoint falls on a shared boundary.
                if midpoint >= segStart, midpoint < segEnd {
                    let trimmed = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        texts.append(trimmed)
                    }
                }
                i += 1
            }

            speakerSegments[idx].text = texts.joined(separator: " ")
        }
    }

    // MARK: - "You" Speaker

    /// Adds a "You" speaker to the meeting for mic-sourced transcript segments.
    /// Creates SpeakerSegment entries and labels transcript segments as "You".
    func addYouSpeaker(for meetingID: UUID) {
        let store = MeetingStore.shared
        guard let meetingIdx = store.meetings.firstIndex(where: { $0.id == meetingID }) else { return }

        let micSegments = store.meetings[meetingIdx].segments.filter { $0.audioSource == .microphone }
        guard !micSegments.isEmpty else { return }

        let youSpeakerID = "you-local-mic"
        var speakers = store.meetings[meetingIdx].speakers
        var speakerSegments = store.meetings[meetingIdx].speakerSegments

        if !speakers.contains(where: { $0.id == youSpeakerID }) {
            speakers.append(Speaker(id: youSpeakerID, name: "You", color: AppThemeConstants.speakerTeal))
        }

        // Create SpeakerSegment entries for mic-sourced transcript segments
        for segment in micSegments {
            let isDuplicate = speakerSegments.contains { existing in
                existing.speakerId == youSpeakerID
                    && abs(existing.startTime - segment.startTime) < AppConstants.Diarization.segmentDedupTolerance
            }
            guard !isDuplicate else { continue }
            speakerSegments.append(SpeakerSegment(
                speakerId: youSpeakerID,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                confidence: 1.0
            ))
        }

        // Label mic-sourced transcript segments as "You"
        for (segIdx, segment) in store.meetings[meetingIdx].segments.enumerated()
            where segment.audioSource == .microphone && segment.speakerLabel == nil
        {
            store.meetings[meetingIdx].segments[segIdx].speakerLabel = "You"
        }

        store.updateSpeakerData(for: meetingID, speakers: speakers, speakerSegments: speakerSegments)
        logger.info("Added 'You' speaker with \(micSegments.count) mic segments")
    }
}
