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
    // Extension-visible: +LongRecording
    /// The streaming Sortformer, for the long-recording pass that feeds it the file in chunks.
    var streamingDiarizer: SortformerDiarizer? {
        sortformerDiarizer
    }

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

    /// Reports what each source is actually contributing to the session timeline.
    ///
    /// The saved file is written straight from the capture tap, so it can be perfectly audible while
    /// the timeline the models read is silent — and nothing in between says so. This makes that gap
    /// visible instead of leaving "the recording may be silent" as the only clue.
    private var timelineDiagnostics = TimelineContributionLog()

    // Extension-visible: +BatchASR
    /// The batch transcriber's words, timed against the session.
    ///
    /// Kept so the accurate text can be poured into the live transcript's segments rather than
    /// replacing them — see `TranscriptRealignment`. Empty when the pass produced no timings.
    var lastBatchWords: [TranscriptRealignment.TimedWord] = []

    /// Reusable AVAudioConverters for efficient resampling — one per capture source, lazily created
    /// and rebuilt only when that source's own input format changes.
    private var resamplers: [AudioSource: AVAudioConverter] = [:]
    private var resamplerInputFormats: [AudioSource: AVAudioFormat] = [:]

    // MARK: - Streaming State

    /// Counter to throttle how often we call process() (not every buffer) — used by batch fallback
    private var samplesAccumulatedSinceLastProcess: Int = 0

    /// The session's audio, mixed onto one timeline. Every capture source writes at the position it
    /// was heard at, so this stays the meeting's own timeline however many sources are running.
    private var mixer = AudioTimelineMixer(
        sampleRate: 16000,
        capacity: AudioTimelineMixer.capacity(
            forPhysicalMemory: ProcessInfo.processInfo.physicalMemory,
            availableMemory: AudioTimelineMixer.availableSystemMemory()
        )
    )

    // Extension-visible: +BatchASR
    /// The accumulated session audio, 16 kHz mono Float32.
    var audioBuffer: [Float] {
        mixer.samples
    }

    /// How much of the session the post-recording pass will get to hear, or `nil` when it will hear
    /// all of it. A value means the buffer filled and the rest of the meeting was dropped, so the
    /// live transcript for that stretch has to be kept rather than replaced by a result that never
    /// heard it — see `TranscriptReplacement`.
    var heardDuration: TimeInterval? {
        mixer.heardDuration
    }

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
        mixer.take()
    }

    /// Frees the accumulated audio without reading it, for when the recording is being processed
    /// from its file instead and the buffer is only holding memory that the models are about to need.
    func discardAudioBuffer() {
        mixer.removeAll()
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

    /// Declares where a capture source's audio belongs on the session timeline.
    ///
    /// Call it whenever a source starts, including when one resumes mid-recording — a capture
    /// device's own clock restarts from zero every time it is toggled, so only the session knows
    /// where the audio it delivers next belongs.
    func beginSource(_ source: AudioSource, atSessionTime time: TimeInterval) {
        guard isEnabled else { return }
        mixer.beginSource(source, atSessionTime: time)
    }

    /// Accumulate audio for post-recording diarization and batch transcription.
    /// All audio is mixed onto one 16 kHz timeline and processed after recording stops, which gives
    /// Sortformer full context over the entire conversation for maximum accuracy.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from source: AudioSource) {
        guard isEnabled else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, buffer.format.channelCount > 0 else { return }
        accumulateBatchBuffer(buffer, from: source)
    }

    /// Convert to 16kHz mono Float32 and mix into the session timeline.
    private func accumulateBatchBuffer(_ buffer: AVAudioPCMBuffer, from source: AudioSource) {
        guard let floatSamples = convertBufferToFloatArray(buffer, from: source) else {
            timelineDiagnostics.recordDroppedConversion(from: source, logger: logger)
            return
        }
        timelineDiagnostics.record(floatSamples, from: source, logger: logger)
        let wasFull = mixer.didDropAudio
        mixer.write(floatSamples, from: source)
        if mixer.didDropAudio, !wasFull {
            let capacityMB = mixer.capacity * MemoryLayout<Float>.size / 1_048_576
            let capacityMinutes = Int(mixer.duration / 60)
            logger.warning(
                """
                Session audio buffer full (\(capacityMinutes)min / ~\(capacityMB)MB) — dropping further audio. \
                The rest of this recording keeps its live transcript instead of the batch one.
                """
            )
        }
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

        let allUpdates = Self.speakerUpdates(from: timeline)

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

    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized, !audioBuffer.isEmpty else { return nil }
        guard let diarizer = batchDiarizer else {
            mixer.removeAll()
            return nil
        }

        let sr = Int(sampleRate)
        let capturedLogger = logger
        let bufferCopy = mixer.take()

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

    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer, from source: AudioSource) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, buffer.format.channelCount > 0, let targetFormat else { return nil }

        if buffer.format == targetFormat, let channelData = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        // One converter per source. The mic and the system tap rarely share a format, and a single
        // shared converter would be torn down and rebuilt on every buffer as the two alternate —
        // paying for the rebuild each time and losing the resampler's carried-over state with it.
        if resamplers[source] == nil || resamplerInputFormats[source] != buffer.format {
            guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
            converter.primeMethod = .none
            resamplers[source] = converter
            resamplerInputFormats[source] = buffer.format
        }

        guard let converter = resamplers[source] else { return nil }
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
        sortformerDiarizer?.reset()
        mixer.removeAll()
        lastError = nil
        resamplers.removeAll()
        resamplerInputFormats.removeAll()
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
