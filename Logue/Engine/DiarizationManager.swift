@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation
import os.log

/// Manages speaker diarization using FluidAudio's Sortformer streaming diarizer.
/// Feeds audio buffers in real-time and gets speaker labels with ~1s latency.
///
/// Thread safety: All mutable state is protected by `@MainActor`.
@Observable
@MainActor
final class DiarizationManager {
    // Extension-visible: +BatchASR
    let logger = Logger(subsystem: AppConstants.bundleID, category: "DiarizationManager")

    // MARK: - Model Cache

    /// Cached compiled Sortformer models — persists across recording sessions.
    private static var cachedSortformerModels: SortformerModels?
    /// Cached old-style models for fallback batch diarization.
    private static var cachedBatchModels: DiarizerModels?
    // Extension-visible: +BatchASR
    /// Cached Parakeet TDT ASR models — persists across recording sessions.
    static var cachedAsrModels: AsrModels?
    // Extension-visible: +BatchASR
    /// Cached Silero VAD manager — persists across recording sessions.
    static var cachedVadManager: VadManager?

    private static let staticLogger = Logger(subsystem: AppConstants.bundleID, category: "DiarizationManager")

    /// Pre-loads all three model types into the static cache at app startup.
    /// Eliminates the model-download stall on the first recording session.
    /// Safe to call concurrently with `initialize()` — both guard against re-download.
    static func prewarmGlobalCache() async {
        if cachedSortformerModels == nil {
            do {
                cachedSortformerModels = try await SortformerModels.loadFromHuggingFace(
                    config: .balancedV2_1, computeUnits: .all, progressHandler: nil
                )
                staticLogger.info("Global Sortformer model cache warmed")
            } catch {
                staticLogger.info("Global Sortformer pre-warm skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        if cachedAsrModels == nil {
            do {
                cachedAsrModels = try await AsrModels.downloadAndLoad(progressHandler: nil)
                staticLogger.info("Global ASR model cache warmed")
            } catch {
                staticLogger.info("Global ASR pre-warm skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        if cachedVadManager == nil {
            do {
                let vadConfig = VadConfig(
                    defaultThreshold: AppConstants.Diarization.vadThreshold,
                    computeUnits: .all
                )
                cachedVadManager = try await VadManager(config: vadConfig)
                staticLogger.info("Global VAD model cache warmed")
            } catch {
                staticLogger.info("Global VAD pre-warm skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Diarizers

    private var sortformerDiarizer: SortformerDiarizer?
    /// Old-style batch diarizer — kept as fallback for post-recording if Sortformer unavailable.
    private var batchDiarizer: DiarizerManager?
    // Extension-visible: +BatchASR
    /// Parakeet TDT batch ASR — initialized lazily on first post-recording transcription.
    var asrManager: AsrManager?
    // Extension-visible: +BatchASR
    /// Silero VAD — initialized lazily, used to filter silence hallucinations from batch ASR output.
    var vadManager: VadManager?

    /// Exposes the underlying batch diarizer for SpeakerManager operations (auto-merge).
    var fluidDiarizerForMerge: DiarizerManager? {
        batchDiarizer
    }

    private var isInitialized = false
    // Extension-visible: +BatchASR
    let sampleRate: Float = 16000.0

    /// Target format for diarization: 16 kHz mono Float32.
    private var targetFormat: AVAudioFormat?

    /// Reusable AVAudioConverter for efficient resampling (lazy-initialized per input format)
    private var resampler: AVAudioConverter?
    private var resamplerInputFormat: AVAudioFormat?

    // MARK: - Streaming State

    /// Counter to throttle how often we call process() (not every buffer) — used by batch fallback
    private var samplesAccumulatedSinceLastProcess: Int = 0

    // Extension-visible: +BatchASR
    /// Audio buffer for batch fallback (only used if Sortformer init fails)
    var audioBuffer: [Float] = []
    private let maxBufferSeconds: Float = 1800.0 // 30 minutes max to limit memory (~115 MB at 16kHz mono)

    // MARK: - Configuration

    var config: DiarizerConfig = .init()
    var isEnabled: Bool = true

    /// Model download progress (0.0–1.0). Observable for UI.
    var modelDownloadProgress: Double = 0.0

    // MARK: - State

    var lastError: (any Error)?

    /// Whether Sortformer streaming is active (vs batch fallback)
    private(set) var isStreamingActive = false

    init(
        config: DiarizerConfig = DiarizerConfig(),
        isEnabled: Bool = true
    ) {
        self.config = config
        self.isEnabled = isEnabled
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
        )
    }

    // MARK: - Initialization

    // swiftlint:disable:next function_body_length
    func initialize() async throws {
        guard isEnabled else {
            logger.info("Diarization is disabled")
            return
        }

        // Try Sortformer first (streaming, preferred)
        // Use balancedV2_1: larger FIFO (188 vs 40) handles overlapping speakers in meetings
        do {
            var meetingTimelineConfig = DiarizerTimelineConfig(
                numSpeakers: 4,
                frameDurationSeconds: 0.08,
                onsetThreshold: AppConstants.Diarization.onsetThreshold,
                offsetThreshold: AppConstants.Diarization.offsetThreshold,
                onsetPadFrames: 2, // ~160ms onset padding
                offsetPadFrames: 4, // ~320ms tail padding
                minFramesOn: 6, // Filter <480ms noise bursts
                minFramesOff: 4 // Close gaps <320ms between same speaker
            )
            let sortformer = SortformerDiarizer(config: .balancedV2_1, timelineConfig: meetingTimelineConfig)
            let models: SortformerModels
            if let cached = Self.cachedSortformerModels {
                models = cached
                logger.info("Reusing cached Sortformer models")
            } else {
                models = try await SortformerModels.loadFromHuggingFace(
                    config: .balancedV2_1,
                    computeUnits: .all,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.modelDownloadProgress = progress.fractionCompleted
                        }
                    }
                )
                Self.cachedSortformerModels = models
                logger.info("Sortformer models loaded and cached")
            }
            sortformer.initialize(models: models)
            sortformerDiarizer = sortformer
            isStreamingActive = true
            isInitialized = true
            logger.info("Sortformer streaming diarizer initialized (latency: ~1s)")
            // Pre-warm ASR + VAD during recording so post-recording processing starts immediately.
            Task { [weak self] in await self?.prewarmModels() }
            return
        } catch {
            logger.warning("Sortformer init failed, falling back to batch diarizer: \(error.localizedDescription, privacy: .public)")
        }

        // Fallback to batch diarizer — used when Sortformer init fails (e.g., model download error).
        // Also provides SpeakerManager for autoMergeSpeakers() post-recording.
        do {
            batchDiarizer = DiarizerManager(config: config)
            let models: DiarizerModels
            if let cached = Self.cachedBatchModels {
                models = cached
                logger.info("Reusing cached batch diarizer models")
            } else {
                models = try await DiarizerModels.downloadIfNeeded()
                Self.cachedBatchModels = models
                logger.info("Batch diarizer models loaded and cached")
            }
            batchDiarizer?.initialize(models: models)
            isInitialized = true
            isStreamingActive = false
            logger.info("Batch diarizer initialized (fallback)")
        } catch {
            logger.error("Failed to initialize diarizer: \(error.localizedDescription, privacy: .public)")
            lastError = error
            throw error
        }
    }

    enum DiarizationError: LocalizedError {
        case audioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .audioFormatUnavailable: "Cannot initialize audio format for diarization."
            }
        }
    }

    // MARK: - Known Speakers

    /// Seed the diarizer with speaker embeddings from a previous recording session.
    func initializeKnownSpeakers(_ appSpeakers: [Speaker]) async {
        // For batch diarizer fallback
        if let diarizer = batchDiarizer {
            let speakerManager = diarizer.speakerManager
            var seededCount = 0
            for appSpeaker in appSpeakers {
                guard let embedding = appSpeaker.embedding, !embedding.isEmpty else { continue }
                await speakerManager.upsertSpeaker(
                    id: appSpeaker.id,
                    currentEmbedding: embedding,
                    duration: 0,
                    isPermanent: true
                )
                seededCount += 1
            }
            if seededCount > 0 {
                logger.info("Seeded batch diarizer with \(seededCount) known speakers")
            }
        }

        // Sortformer enrollment requires raw audio samples via enrollSpeaker(withAudio:named:),
        // not embedding vectors. Our Speaker model stores float embeddings, not raw audio.
        // Future: store enrollment audio (first ~10s of speech) in Speaker model to enable
        // Sortformer speaker priming via its enrollSpeaker() API.
        if isStreamingActive, !appSpeakers.isEmpty {
            logger.info("Sortformer enrollment requires raw audio — skipping known speaker priming for \(appSpeakers.count) speakers")
        }
    }

    // MARK: - Audio Accumulation

    /// Copy and clear the audio buffer in one atomic MainActor step.
    /// Call this before running transcription and diarization in parallel so both
    /// receive the same snapshot without a buffer-clear race.
    func takeAudioBuffer() -> [Float] {
        let copy = audioBuffer
        audioBuffer.removeAll(keepingCapacity: false)
        return copy
    }

    /// Pre-warm Parakeet TDT ASR and Silero VAD models in the background during recording.
    /// Eliminates the model-load delay from the post-recording pipeline on every session.
    func prewarmModels() async {
        guard isEnabled else { return }
        if asrManager == nil {
            do {
                let models: AsrModels
                if let cached = Self.cachedAsrModels {
                    models = cached
                } else {
                    models = try await AsrModels.downloadAndLoad(progressHandler: nil)
                    Self.cachedAsrModels = models
                }
                let manager = AsrManager()
                try await manager.loadModels(models)
                asrManager = manager
                logger.info("ASR models pre-warmed during recording")
            } catch {
                logger.info("ASR pre-warm skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard vadManager == nil else { return }
        do {
            if let cached = Self.cachedVadManager {
                vadManager = cached
            } else {
                let vadConfig = VadConfig(
                    defaultThreshold: AppConstants.Diarization.vadThreshold,
                    computeUnits: .all
                )
                let vad = try await VadManager(config: vadConfig)
                Self.cachedVadManager = vad
                vadManager = vad
            }
            logger.info("VAD model pre-warmed during recording")
        } catch {
            logger.info("VAD pre-warm skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Accumulate audio for post-recording diarization.
    /// All audio is buffered at 16kHz and processed after recording stops via `processCompleteRecording()`.
    /// This gives Sortformer full context over the entire conversation for maximum accuracy.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isEnabled else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, buffer.format.channelCount > 0 else { return }
        accumulateBatchBuffer(buffer)
    }

    /// Convert to 16kHz mono Float32 and accumulate for post-recording processing.
    private func accumulateBatchBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatSamples = convertBufferToFloatArray(buffer) else { return }
        let maxBufferSecs = maxBufferSeconds
        let maxSamples = Int(sampleRate) * Int(maxBufferSecs)
        guard audioBuffer.count < maxSamples else {
            if audioBuffer.count == maxSamples || (audioBuffer.count > maxSamples && audioBuffer.count - floatSamples.count < maxSamples) {
                let bufferMB = maxSamples * 4 / 1_048_576
                logger.warning("Diarization buffer full (\(maxBufferSecs)s / ~\(bufferMB)MB) — dropping new audio")
            }
            return
        }
        if audioBuffer.isEmpty {
            audioBuffer.reserveCapacity(Int(sampleRate * 600))
        }
        audioBuffer.append(contentsOf: floatSamples)
    }

    // MARK: - Post-Recording Complete Processing

    /// Process the full accumulated audio buffer using Sortformer's `processComplete()`.
    /// This gives the model complete context over the entire conversation for maximum accuracy.
    /// Call after recording stops — NOT during recording.
    func processCompleteRecording() async -> [SortformerSpeakerUpdate]? {
        guard !audioBuffer.isEmpty else {
            logger.info("No audio accumulated for post-recording diarization")
            return nil
        }
        let buffer = takeAudioBuffer()
        return await processCompleteWith(buffer)
    }

    /// Buffer-accepting variant — use with `takeAudioBuffer()` to run Sortformer
    /// concurrently with `transcribeBuffer(_:)` on the same snapshot.
    func processCompleteWith(_ buffer: [Float]) async -> [SortformerSpeakerUpdate]? {
        guard !buffer.isEmpty else { return nil }

        let durationSeconds = String(format: "%.1f", Float(buffer.count) / sampleRate)
        logger.info("Processing \(buffer.count) samples (\(durationSeconds)s) — post-recording pass (balancedV2_1)")

        // highContextV2_1 crashes inside FluidAudio's processComplete() chunker: its rc=40 right-context
        // requirement exceeds the size of edge chunks (coreFrames goes negative → fatal range assertion).
        // balancedV2_1 handles processComplete() safely and still gives good accuracy because the full
        // recording is submitted in one pass rather than streamed one chunk at a time.
        guard let diarizer = sortformerDiarizer else {
            logger.warning("Sortformer diarizer not initialized — skipping post-recording pass")
            return nil
        }
        let capturedLogger = logger

        let result: DiarizerTimeline? = await Task.detached {
            do {
                capturedLogger.info("Post-recording diarizer: balancedV2_1 (full-audio batch pass)")
                return try diarizer.processComplete(buffer, finalizeOnCompletion: true)
            } catch {
                capturedLogger.error("Sortformer processComplete failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let timeline = result else { return nil }

        var allUpdates: [SortformerSpeakerUpdate] = []
        for (speakerIndex, speaker) in timeline.speakers {
            for segment in speaker.finalizedSegments {
                allUpdates.append(SortformerSpeakerUpdate(
                    speakerIndex: speakerIndex,
                    speakerName: speaker.name ?? "Speaker \(speakerIndex + 1)",
                    startTime: TimeInterval(segment.startTime),
                    endTime: TimeInterval(segment.endTime)
                ))
            }
        }

        if allUpdates.isEmpty {
            logger.info("Sortformer processComplete: no segments (recording may be very short or silent)")
        } else {
            let speakerCount = Set(allUpdates.map(\.speakerIndex)).count
            logger.info("Sortformer processComplete: \(allUpdates.count) segments, \(speakerCount) speakers")
        }
        return allUpdates.isEmpty ? nil : allUpdates
    }

    // Batch ASR (transcribeCompleteRecording, transcribeBuffer, filterWithVAD,
    // segmentsFromTokenTimings) lives in DiarizationManager+BatchASR.swift.

    // MARK: - Batch Fallback (used when Sortformer unavailable)

    /// Start periodic batch processing (only used in fallback mode).
    func startPeriodicProcessing(onUpdate: @escaping (DiarizationResult) -> Void) {
        guard !isStreamingActive else { return } // Sortformer handles this

        // Legacy periodic processing for batch fallback
        let periodicTask = Task { [weak self] in
            do { try await Task.sleep(for: AppConstants.Delays.batchDiarizationInitialDelay) } catch { return }
            var interval: Duration = .seconds(15)
            let maxInterval: Duration = .seconds(120)

            while !Task.isCancelled {
                if let result = await self?.processIncrementalChunk() {
                    onUpdate(result)
                }
                interval = min(interval + .seconds(15), maxInterval)
                do { try await Task.sleep(for: interval) } catch { break }
            }
        }
        self.periodicTask = periodicTask
    }

    private var periodicTask: Task<Void, Never>?
    private var lastProcessedSampleIndex: Int = 0
    private var lastProcessedTime: TimeInterval = 0

    func stopPeriodicProcessing() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    private func processIncrementalChunk() async -> DiarizationResult? {
        guard let diarizer = batchDiarizer else { return nil }
        let currentCount = audioBuffer.count
        let newSampleCount = currentCount - lastProcessedSampleIndex
        let minChunkSamples = Int(sampleRate * 15)
        guard newSampleCount >= minChunkSamples else { return nil }

        let startIdx = lastProcessedSampleIndex
        let chunkSamples = Array(audioBuffer[startIdx ..< currentCount])
        let sr = Int(sampleRate)
        let startTime = lastProcessedTime

        lastProcessedSampleIndex = currentCount
        lastProcessedTime += Double(newSampleCount) / Double(sampleRate)

        let capturedLogger = logger
        let result: DiarizationResult? = await Task.detached {
            do {
                return await try diarizer.performCompleteDiarization(chunkSamples, sampleRate: sr, atTime: startTime)
            } catch {
                capturedLogger.error("Incremental diarization failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard !Task.isCancelled, let result else { return nil }
        return result
    }

    func processRemainingChunk() async -> DiarizationResult? {
        guard let diarizer = batchDiarizer else { return nil }
        let currentCount = audioBuffer.count
        let newSampleCount = currentCount - lastProcessedSampleIndex
        guard newSampleCount > 0 else { return nil }

        let startIdx = lastProcessedSampleIndex
        let chunkSamples = Array(audioBuffer[startIdx ..< currentCount])
        let sr = Int(sampleRate)
        let startTime = lastProcessedTime

        lastProcessedSampleIndex = currentCount
        lastProcessedTime += Double(newSampleCount) / Double(sampleRate)

        let capturedLogger = logger
        let result: DiarizationResult? = await Task.detached {
            do {
                return await try diarizer.performCompleteDiarization(chunkSamples, sampleRate: sr, atTime: startTime)
            } catch {
                capturedLogger.error("Remaining chunk diarization failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value

        guard let result else { return nil }
        return result
    }

    func finishProcessing() async -> DiarizationResult? {
        stopPeriodicProcessing()
        guard isEnabled, isInitialized, !audioBuffer.isEmpty else { return nil }
        guard let diarizer = batchDiarizer else {
            audioBuffer.removeAll(keepingCapacity: false)
            return nil
        }

        let bufferCopy = audioBuffer
        let sr = Int(sampleRate)
        let capturedLogger = logger
        audioBuffer.removeAll(keepingCapacity: false)

        return await Task.detached {
            do {
                return await try diarizer.performCompleteDiarization(bufferCopy, sampleRate: sr)
            } catch {
                capturedLogger.error("Final diarization failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    // MARK: - Audio Conversion

    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, buffer.format.channelCount > 0, let targetFormat else { return nil }

        if buffer.format == targetFormat, let channelData = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        if resampler == nil || resamplerInputFormat != buffer.format {
            resampler = AVAudioConverter(from: buffer.format, to: targetFormat)
            resampler?.primeMethod = .none
            resamplerInputFormat = buffer.format
        }

        guard let converter = resampler else { return nil }
        guard buffer.format.sampleRate > 0 else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount((Double(frameCount) * ratio).rounded(.up))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var consumed = false
        var nsError: NSError?
        let status = converter.convert(to: outputBuffer, error: &nsError) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            logger.warning("Audio conversion failed: \(nsError?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        }
        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    // MARK: - Reset

    func reset() {
        stopPeriodicProcessing()
        sortformerDiarizer?.reset()
        audioBuffer.removeAll()
        lastError = nil
        resampler = nil
        resamplerInputFormat = nil
        lastProcessedSampleIndex = 0
        lastProcessedTime = 0
        samplesAccumulatedSinceLastProcess = 0
    }
}

// MARK: - Sortformer Update Model

/// Lightweight struct representing a speaker segment from Sortformer streaming.
struct SortformerSpeakerUpdate {
    let speakerIndex: Int
    let speakerName: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
