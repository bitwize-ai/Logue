import AVFoundation
import FluidAudio
import Foundation

/// The post-recording pass for a meeting that outgrew the in-memory audio timeline.
///
/// The usual pass hands Sortformer and Parakeet the whole recording at once, which is the most
/// accurate thing to do and costs memory in proportion to the meeting's length. Past a few hours
/// that stops being affordable, and the recording used to simply stop being processed — speakers
/// and batch-quality transcript ended wherever the buffer filled.
///
/// It does not have to. The recording is already on disk for playback, and neither model actually
/// needs it in one piece: Parakeet transcribes disk-backed in constant memory, and Sortformer is a
/// streaming model whose speaker identities live in state carried between chunks rather than in the
/// audio. So a long meeting is read back from its own file a chunk at a time and processed to the
/// end, at the same quality, with memory that does not grow with the meeting.
extension DiarizationManager {
    struct LongRecordingResult {
        let segments: [TranscriptSegment]
        let speakers: [SortformerSpeakerUpdate]
    }

    /// Transcribes and diarizes a persisted recording by streaming it from disk.
    /// Times are relative to the start of the file, matching what the in-memory pass produces.
    func processRecordingFile(_ url: URL) async -> LongRecordingResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("Long-recording pass: audio file missing")
            return nil
        }

        async let transcriptTask = transcribeRecordingFile(url)
        let speakers = await diarizeRecordingFile(url)
        let segments = await transcriptTask

        guard segments != nil || speakers != nil else { return nil }
        return LongRecordingResult(segments: segments ?? [], speakers: speakers ?? [])
    }

    // MARK: - Transcription

    /// Parakeet over the file. `transcribe(_ url:)` switches itself to disk-backed chunking above its
    /// streaming threshold, so memory stays flat no matter how long the meeting ran.
    private func transcribeRecordingFile(_ url: URL) async -> [TranscriptSegment]? {
        guard let asr = await ensureAsrManager() else { return nil }
        let capturedLogger = logger

        let result: ASRResult? = await Task.detached {
            do {
                return try await asr.transcribe(url, source: .system)
            } catch {
                capturedLogger.error("Long-recording ASR failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let result else { return nil }
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.info("Long-recording ASR returned an empty transcript")
            return nil
        }
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            logger.warning("Long-recording ASR: no token timings — returning one segment")
            return [TranscriptSegment(text: trimmed, startTime: 0, endTime: result.duration)]
        }

        let segments = segmentsFromTokenTimings(timings)
        logger.info("Long-recording ASR: \(segments.count) segments from \(timings.count) tokens")
        guard !segments.isEmpty else { return nil }
        return await filterWithFileVAD(segments, url: url)
    }

    /// Drops transcript segments that fall outside any detected speech.
    ///
    /// The in-memory pass filters against Silero VAD, and skipping it here would leave the longest
    /// recordings — the ones most likely to contain long stretches of silence for the model to
    /// hallucinate into — as the only ones getting raw output. VAD runs over the file a chunk at a
    /// time like everything else, each chunk's regions shifted onto the recording's timeline.
    private func filterWithFileVAD(_ segments: [TranscriptSegment], url: URL) async -> [TranscriptSegment] {
        guard let vad = await ensureVadManager() else {
            logger.warning("VAD unavailable — returning the long-recording transcript unfiltered")
            return segments
        }

        let config = VadSegmentationConfig(
            minSpeechDuration: AppConstants.Diarization.vadMinSpeechDuration,
            minSilenceDuration: AppConstants.Diarization.vadMinSilenceDuration,
            speechPadding: AppConstants.Diarization.vadSpeechPadding,
            negativeThresholdOffset: AppConstants.Diarization.vadNegativeThresholdOffset
        )
        let rate = Double(sampleRate)
        let chunkSeconds = AppConstants.Diarization.longRecordingChunkSeconds
        let capturedLogger = logger

        // Off the MainActor: this reads and resamples the whole recording, hundreds of times over a
        // long one. Left on the main thread it would hitch the UI for the entire post-recording pass,
        // while the diarization pass running beside it is detached and does not.
        let regions: [(start: TimeInterval, end: TimeInterval)]? = await Task.detached {
            do {
                var found: [(start: TimeInterval, end: TimeInterval)] = []
                // Streamed rather than collected: awaiting VAD per chunk is exactly the case the
                // reader is an iterator for.
                var reader = try AudioFileChunkReader(url: url, chunkSeconds: chunkSeconds, sampleRate: rate)
                while let chunk = try reader.next() {
                    let offset = TimeInterval(Double(chunk.offset) / rate)
                    let speech = try await vad.segmentSpeech(chunk.samples, config: config)
                    found.append(contentsOf: speech.map { (offset + $0.startTime, offset + $0.endTime) })
                }
                return found
            } catch {
                capturedLogger.warning(
                    "Long-recording VAD failed, returning unfiltered: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }.value

        guard let regions else { return segments }

        guard !regions.isEmpty else { return segments }
        let filtered = segments.filter { segment in
            regions.contains { $0.end > segment.startTime && $0.start < segment.endTime }
        }
        let removed = segments.count - filtered.count
        if removed > 0 {
            logger.info("Long-recording VAD removed \(removed) silence segment(s), \(filtered.count) kept")
        }
        // Guard against over-filtering: a VAD pass that rejects everything is wrong about the audio,
        // not right about the transcript.
        return filtered.isEmpty ? segments : filtered
    }

    // MARK: - Diarization

    /// Sortformer over the file, fed chunk by chunk through the streaming API.
    ///
    /// Speaker identity survives the chunking because it lives in the model's `spkcache`/`fifo`
    /// state, carried from one chunk to the next, rather than being re-derived per chunk. Numbering
    /// therefore stays consistent from the first minute to the last.
    ///
    /// It is not identical to the whole-buffer call: that one accumulates every chunk's predictions
    /// and rebuilds the timeline from all of them at the end, where this commits each chunk as it
    /// goes. Expect diarization on this route to be a little rougher at the seams. It is the route
    /// for recordings the other one cannot process at all, so the comparison that matters is against
    /// having no speaker labels for the second half of a meeting.
    private func diarizeRecordingFile(_ url: URL) async -> [SortformerSpeakerUpdate]? {
        guard let diarizer = streamingDiarizer else {
            logger.warning("Long-recording pass: Sortformer not initialized")
            return nil
        }

        let chunkSeconds = AppConstants.Diarization.longRecordingChunkSeconds
        let rate = Double(sampleRate)
        let capturedLogger = logger

        let timeline: DiarizerTimeline? = await Task.detached {
            do {
                diarizer.reset()
                var chunks = 0
                try AudioFileChunkReader.read(url, chunkSeconds: chunkSeconds, sampleRate: rate) { samples, _ in
                    _ = try diarizer.process(samples: samples)
                    chunks += 1
                }
                guard chunks > 0 else { return nil }
                _ = try diarizer.finalizeSession()
                capturedLogger.info("Long-recording diarization: \(chunks) chunks streamed")
                return diarizer.timeline
            } catch {
                capturedLogger.error(
                    "Long-recording diarization failed: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }.value

        guard let timeline else { return nil }
        let updates = Self.speakerUpdates(from: timeline)
        guard !updates.isEmpty else {
            logger.info("Long-recording diarization produced no speaker segments")
            return nil
        }
        let speakerCount = Set(updates.map(\.speakerIndex)).count
        logger.info("Long-recording diarization: \(updates.count) segments, \(speakerCount) speakers")
        return updates
    }

    // MARK: - Shared

    /// Flattens a Sortformer timeline into the app's speaker updates.
    static func speakerUpdates(from timeline: DiarizerTimeline) -> [SortformerSpeakerUpdate] {
        var updates: [SortformerSpeakerUpdate] = []
        for (speakerIndex, speaker) in timeline.speakers {
            for segment in speaker.finalizedSegments {
                updates.append(SortformerSpeakerUpdate(
                    speakerIndex: speakerIndex,
                    speakerName: speaker.name ?? "Speaker \(speakerIndex + 1)",
                    startTime: TimeInterval(segment.startTime),
                    endTime: TimeInterval(segment.endTime)
                ))
            }
        }
        return updates
    }
}
