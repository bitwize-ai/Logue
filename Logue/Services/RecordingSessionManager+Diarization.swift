import FluidAudio
import Foundation
import os.log

/// Diarization-related methods extracted from RecordingSessionManager.
/// Handles speaker detection, merging, alignment, and Sortformer streaming updates.
extension RecordingSessionManager {
    /// Whether the diarization pass in flight belongs to this meeting.
    ///
    /// `isDiarizing` on its own is global, and the summary panel reads it as if it were
    /// per-meeting — which put a spinner over a finished meeting's saved Smart Minutes for the
    /// whole of another meeting's pass, because that branch is taken ahead of the content.
    func isDiarizing(for meetingID: UUID) -> Bool {
        diarizingMeetingID == meetingID
    }

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
    /// - Parameter savedAudio: What was written to disk for this session, and whether its timings
    ///   describe the meeting. The long-recording pass may only read a file that does.
    /// - Parameter sessionDuration: How long this session actually ran, for checking that the saved
    ///   file covers all of it rather than merely lining up with it.
    func processDiarization(
        for meetingID: UUID,
        diarizer: DiarizationManager,
        sessionStart: TimeInterval,
        savedAudio: SavedRecording,
        sessionDuration: TimeInterval
    ) async {
        diarizingMeetingID = meetingID
        diarizationStage = "Identifying speakers…"

        // Primary path: Sortformer processComplete on full audio buffer
        if await processSortformerDiarization(
            for: meetingID,
            diarizer: diarizer,
            sessionStart: sessionStart,
            savedAudio: savedAudio,
            sessionDuration: sessionDuration
        ) {
            return
        }

        // Fallback: batch DiarizerManager
        diarizationStage = "Identifying speakers…"
        logger.info("Starting batch post-recording diarization for meeting \(meetingID)...")

        guard let result = await diarizer.finishProcessing() else {
            logger.warning("Post-recording diarization returned no result (empty audio or not initialized)")
            diarizingMeetingID = nil
            diarizationStage = ""
            return
        }
        logger.info("Post-recording diarization got \(result.segments.count) segments")

        // Map FluidAudio results into our Speaker + SpeakerSegment models
        let store = MeetingStore.shared
        guard let meeting = store.meetings.first(where: { $0.id == meetingID }) else {
            diarizingMeetingID = nil
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

        diarizingMeetingID = nil
        diarizationStage = ""
        logger.info("Diarization complete: \(speakers.count) speakers, \(speakerSegments.count) segments")
    }

    /// Primary diarization path: transcribes and diarizes the session, then aligns the transcript
    /// with the speaker segments.
    /// Returns `true` when it handled diarization (streaming was active); `false` to fall back to batch.
    private func processSortformerDiarization(
        for meetingID: UUID,
        diarizer: DiarizationManager,
        sessionStart: TimeInterval,
        savedAudio: SavedRecording,
        sessionDuration: TimeInterval
    ) async -> Bool {
        guard diarizer.isStreamingActive else { return false }
        logger.info("Starting parallel Sortformer + batch ASR for meeting \(meetingID)...")

        let pass = await runBatchPass(
            diarizer: diarizer,
            savedAudio: savedAudio,
            sessionDuration: sessionDuration
        )
        let sortformerUpdates = pass.speakers
        let batchSegments = pass.segments

        // The transcript the user watched being written is the transcript they keep.
        //
        // Replacing it with the batch result was more accurate word for word, but it re-cut every
        // sentence: a different number of blocks, text merged and split, and the reader's place
        // lost — all arriving silently, a minute after they stopped recording. Speaker identity does
        // not require it. Sortformer produces time ranges, not text, so the labels below apply to
        // the live segments perfectly well, and the transcript never changes under anyone.
        //
        // `batchSegments` is still computed: it is what the speaker timeline is derived from.
        // Note this path applies no `TranscriptReplacement` bound — it does not replace the
        // transcript at all, so there is nothing for one to bound. The disk route in
        // `+LongRecording` is where `heardDuration` does its work.
        // The batch pass is more accurate word for word, but its sentence boundaries are its own.
        // Adopting them re-cut the transcript the user had been reading. So its words are poured
        // into the live segments instead: every line keeps its identity, its start and its end, and
        // only the text inside improves.
        if let batchSegments, !diarizer.lastBatchWords.isEmpty,
           let meeting = MeetingStore.shared.meetings.first(where: { $0.id == meetingID })
        {
            let realigned = TranscriptRealignment.snappedToSentences(
                TranscriptRealignment.realign(
                    live: meeting.segments,
                    words: diarizer.lastBatchWords,
                    sessionStart: sessionStart
                ),
                sessionStart: sessionStart
            )
            MeetingStore.shared.updateSegments(realigned, for: meetingID)
            logger.info(
                "Realigned \(batchSegments.count) batch segment(s) onto \(realigned.count) live line(s)"
            )
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

        diarizingMeetingID = nil
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
