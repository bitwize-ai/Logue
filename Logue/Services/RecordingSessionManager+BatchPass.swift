import FluidAudio
import Foundation

/// Choosing how a finished session gets transcribed and diarized, and how much of it the result may
/// speak for.
///
/// Two questions decide everything here: did the recording fit in memory, and if not, is the file on
/// disk actually this meeting? Getting the second one wrong replaces a correct live transcript with
/// a plausible one at the wrong times, so the answer is carried from the code that saved the file
/// rather than inferred afterwards.
extension RecordingSessionManager {
    // Extension-visible: +Diarization
    /// What the post-recording pass produced, and how much of the session it can speak for.
    struct BatchPassResult {
        var segments: [TranscriptSegment]?
        var speakers: [SortformerSpeakerUpdate]?
        /// Seconds of the session the pass actually heard, or `nil` when it heard all of it.
        var heardDuration: TimeInterval?
    }

    // Extension-visible: +Diarization
    /// Runs Parakeet TDT and Sortformer over the session, from memory when the recording fits and
    /// from its own file on disk when it does not.
    ///
    /// The in-memory timeline is bounded by what the machine can hold, and a long meeting overruns
    /// it. That used to be the end of the story — speakers and batch-quality transcript simply
    /// stopped there. But the recording is already on disk for playback, and neither model needs it
    /// in one piece, so an overrun becomes a change of route rather than a loss.
    ///
    /// The disk route is taken only for a file that persistence reported as being the meeting's
    /// timeline. That fact is carried here rather than re-derived, because every way of working it
    /// out after the fact — the file's length, the elapsed clock — is wrong in exactly the cases
    /// that produce a misaligned file.
    func runBatchPass(
        diarizer: DiarizationManager,
        savedAudio: SavedRecording,
        sessionDuration: TimeInterval
    ) async -> BatchPassResult {
        guard diarizer.heardDuration != nil else {
            // The whole session fitted in memory: the usual pass, on the buffer.
            return await inMemoryPass(diarizer: diarizer, heardDuration: nil)
        }

        guard savedAudio.describesSessionTimeline,
              let audioURL = savedAudio.url,
              FileManager.default.fileExists(atPath: audioURL.path)
        else {
            logger.warning("Recording outgrew memory but its saved audio is not the session timeline")
            return await inMemoryPass(diarizer: diarizer, heardDuration: diarizer.heardDuration)
        }

        // Being on the timeline says the file's timings are right, not that it holds all of the
        // meeting. A source whose writes started failing part-way through leaves a file that begins
        // at zero, lines up perfectly, and simply stops early — and trusting that as the whole
        // session would delete every live segment past its end, which is the loss this change exists
        // to prevent. So coverage is measured rather than assumed.
        let fileDuration = AudioFileChunkReader.duration(of: audioURL) ?? 0
        let coversSession = sessionDuration - fileDuration <= AppConstants.Diarization.recordingCoverageTolerance
        let heardFromFile: TimeInterval? = coversSession ? nil : fileDuration
        if let heardFromFile {
            let held = String(format: "%.0f", heardFromFile)
            let ran = String(format: "%.0f", sessionDuration)
            logger
                .warning(
                    "Saved audio holds \(held, privacy: .public)s of a \(ran, privacy: .public)s session — keeping the live transcript beyond that"
                )
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
            // With no transcript there is nothing to replace, and zero keeps every live segment.
            // Otherwise the result speaks for exactly as much of the session as the file held.
            heardDuration: result.segments.isEmpty ? 0 : heardFromFile
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
                Audio buffer capped with no usable file to fall back on: heard \
                \(String(format: "%.0f", heardDuration), privacy: .public)s of this session — \
                keeping the live transcript beyond that point
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
}
