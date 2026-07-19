import FluidAudio
import Foundation

// MARK: - Batch ASR (Post-Recording Transcription)

extension DiarizationManager {
    /// Run Parakeet TDT batch ASR on the accumulated audio buffer.
    /// Prefer `transcribeBuffer(_:)` with `takeAudioBuffer()` when running concurrently with Sortformer.
    func transcribeCompleteRecording() async -> [TranscriptSegment]? {
        guard !audioBuffer.isEmpty else {
            logger.info("No audio buffer for batch ASR")
            return nil
        }
        return await transcribeBuffer(audioBuffer)
    }

    /// Buffer-accepting variant — use with `takeAudioBuffer()` to run Parakeet TDT
    /// concurrently with `processCompleteWith(_:)` on the same snapshot.
    func transcribeBuffer(_ buffer: [Float]) async -> [TranscriptSegment]? {
        guard !buffer.isEmpty else { return nil }

        if asrManager == nil {
            do {
                let models: AsrModels
                if let cached = Self.cachedAsrModels {
                    models = cached
                    logger.info("Reusing cached ASR models")
                } else {
                    logger.info("Downloading Parakeet TDT models for batch transcription...")
                    models = try await AsrModels.downloadAndLoad(
                        progressHandler: { [weak self] progress in
                            Task { @MainActor in
                                self?.modelDownloadProgress = progress.fractionCompleted
                            }
                        }
                    )
                    Self.cachedAsrModels = models
                    logger.info("ASR models downloaded and cached")
                }
                let manager = AsrManager()
                try await manager.loadModels(models)
                asrManager = manager
            } catch {
                logger.error("Batch ASR init failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        guard let asr = asrManager else { return nil }
        let capturedLogger = logger
        let durationSec = Double(buffer.count) / Double(sampleRate)
        logger.info("Running batch ASR on \(String(format: "%.1f", durationSec))s of audio")

        let result: ASRResult? = await Task.detached {
            do {
                // Use FluidAudio's public batch API, which manages (and resets) the TDT
                // decoder state internally — a fresh one-shot pass over the accumulated buffer.
                return try await asr.transcribe(buffer, source: .system)
            } catch {
                capturedLogger.error("Batch ASR transcription failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let result else { return nil }
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.info("Batch ASR returned empty transcript")
            return nil
        }

        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            logger.warning("Batch ASR: no token timings — returning single segment")
            return [TranscriptSegment(text: trimmed, startTime: 0, endTime: result.duration)]
        }

        let segments = segmentsFromTokenTimings(tokenTimings)
        logger.info("Batch ASR: \(segments.count) segments, \(tokenTimings.count) tokens, RTFx \(String(format: "%.1f", result.rtfx))x")
        guard !segments.isEmpty else { return nil }
        return await filterWithVAD(segments, audioBuffer: buffer)
    }

    /// Filter transcript segments using Silero VAD speech regions.
    /// Removes segments whose time range doesn't overlap any detected speech.
    /// Falls back to unfiltered segments if VAD init or processing fails.
    func filterWithVAD(_ segments: [TranscriptSegment], audioBuffer: [Float]) async -> [TranscriptSegment] {
        if vadManager == nil {
            do {
                if let cached = Self.cachedVadManager {
                    vadManager = cached
                    logger.info("Reusing cached VAD manager")
                } else {
                    logger.info("Loading Silero VAD model...")
                    let vadConfig = VadConfig(
                        defaultThreshold: AppConstants.Diarization.vadThreshold,
                        computeUnits: .all
                    )
                    let vad = try await VadManager(config: vadConfig)
                    Self.cachedVadManager = vad
                    vadManager = vad
                    logger.info("VAD model loaded and cached")
                }
            } catch {
                logger.warning("VAD init failed, skipping silence filtering: \(error.localizedDescription, privacy: .public)")
                return segments
            }
        }

        guard let vad = vadManager else { return segments }

        do {
            let segConfig = VadSegmentationConfig(
                minSpeechDuration: AppConstants.Diarization.vadMinSpeechDuration,
                minSilenceDuration: AppConstants.Diarization.vadMinSilenceDuration,
                speechPadding: AppConstants.Diarization.vadSpeechPadding,
                negativeThresholdOffset: AppConstants.Diarization.vadNegativeThresholdOffset
            )
            let speechRegions = try await vad.segmentSpeech(audioBuffer, config: segConfig)
            guard !speechRegions.isEmpty else { return segments }

            let filtered = segments.filter { seg in
                speechRegions.contains { region in
                    region.endTime > seg.startTime && region.startTime < seg.endTime
                }
            }
            let removed = segments.count - filtered.count
            if removed > 0 {
                logger.info("VAD removed \(removed) silence segment(s), \(filtered.count) kept")
            }
            // Guard against VAD over-filtering: fall back if everything was removed.
            return filtered.isEmpty ? segments : filtered
        } catch {
            logger.warning("VAD filtering failed, returning unfiltered: \(error.localizedDescription, privacy: .public)")
            return segments
        }
    }

    /// Group token-level timings into sentence-like `TranscriptSegment` values.
    /// Splits on silence gaps > 0.8s or when a segment exceeds 30s.
    func segmentsFromTokenTimings(_ timings: [TokenTiming]) -> [TranscriptSegment] {
        guard !timings.isEmpty else { return [] }
        var segments: [TranscriptSegment] = []
        var group: [TokenTiming] = []
        let silenceGap: TimeInterval = 0.8
        let maxDuration: TimeInterval = 30.0

        func flush() {
            guard !group.isEmpty else { return }
            let text = group.map(\.token).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { group.removeAll(); return }
            let sumConf = group.reduce(into: Float(0)) { $0 += $1.confidence }
            let avgConf = sumConf / Float(group.count)
            segments.append(TranscriptSegment(
                text: text,
                startTime: group[0].startTime,
                endTime: group[group.count - 1].endTime,
                confidence: Double(avgConf)
            ))
            group.removeAll()
        }

        for (i, token) in timings.enumerated() {
            if group.isEmpty {
                group.append(token); continue
            }
            let gap = token.startTime - timings[i - 1].endTime
            let segDuration = token.endTime - group[0].startTime
            if gap > silenceGap || segDuration > maxDuration {
                flush()
            }
            group.append(token)
        }
        flush()
        return segments
    }
}
