import AVFoundation
import Foundation
import os.log
import Speech

/// Manages real-time transcription using Apple's SpeechTranscriber API (macOS 26+).
/// Streams audio buffers directly — no chunking, no deduplication, no gap issues.
@Observable
@MainActor
final class SpeechTranscriberEngine {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SpeechTranscriber")

    // MARK: - Public State

    /// Current volatile (in-progress) transcription text — updates rapidly as the user speaks.
    var volatileText: String = ""

    /// Download progress when the speech model needs to be fetched.
    var downloadProgress: Progress?

    /// Whether the engine is set up and actively transcribing.
    var isActive: Bool {
        recognizerTask != nil
    }

    // MARK: - Callbacks

    /// Fired each time a final transcription segment is produced.
    var onFinalSegment: ((TranscriptSegment) -> Void)?

    // MARK: - Configuration

    /// When true, timestamps are derived from streamed audio frames instead of wall-clock time.
    /// Use for offline (faster-than-real-time) transcription where Date() would be wrong.
    var useAudioDrivenTiming = false

    // MARK: - Internals

    private let converter = BufferConverter()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var recognizerTask: Task<Void, any Error>?

    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation

    /// Tracks the end time of the last finalized segment for timestamp calculation.
    private var lastSegmentEndTime: TimeInterval = 0
    private var sessionStartDate: Date?

    /// Audio-driven timing state — frame count and sample rate from streamed buffers.
    private var totalFramesStreamed: Int64 = 0
    private var streamSampleRate: Double = 0

    // MARK: - Locale Configuration

    private static let fallbackLocales: [Locale] = [
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedKingdom)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .canada)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .australia)),
        Locale(identifier: "en-US"),
        Locale(identifier: "en"),
        Locale.current,
    ]

    // MARK: - Init

    init() {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputSequence = stream
        inputBuilder = continuation
    }

    // MARK: - Setup

    /// Set up the transcriber with the given locale and start listening for results.
    /// - Parameter locale: The locale for transcription, or `nil` to use en-US default.
    func setup(locale: Locale? = nil) async throws {
        let targetLocale = locale ?? Locale(
            components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates)
        )

        logger.info("Setting up SpeechTranscriber for locale: \(targetLocale.identifier)")

        transcriber = SpeechTranscriber(
            locale: targetLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        guard let transcriber else {
            logger.error("Failed to create SpeechTranscriber")
            throw SpeechTranscriberError.failedToSetup
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        try await ensureModel(transcriber: transcriber, locale: targetLocale)

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        )

        guard analyzerFormat != nil else {
            logger.error("No compatible audio format found")
            throw SpeechTranscriberError.invalidAudioFormat
        }

        sessionStartDate = Date()
        lastSegmentEndTime = 0

        // Cancel any previous recognizer task to prevent leaks on repeated setup() calls.
        recognizerTask?.cancel()
        let audioDriven = useAudioDrivenTiming
        recognizerTask = Task {
            await self.consumeResults(from: transcriber, audioDriven: audioDriven)
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
            logger.info("SpeechAnalyzer started successfully")
        } catch {
            // Clean up all resources on setup failure to prevent zombie tasks
            recognizerTask?.cancel()
            _ = await recognizerTask?.result // Wait for cancellation to complete
            recognizerTask = nil
            self.transcriber = nil
            analyzer = nil
            analyzerFormat = nil
            logger.error("Failed to start SpeechAnalyzer: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// C-N5: Explicitly @MainActor — accesses actor-isolated state (onFinalSegment, volatileText, etc.)
    @MainActor
    private func consumeResults(from transcriber: SpeechTranscriber, audioDriven: Bool) async {
        do {
            for try await case let result in transcriber.results {
                let rawText = String(result.text.characters)
                if result.isFinal {
                    let elapsed: TimeInterval
                    if audioDriven {
                        elapsed = streamSampleRate > 0
                            ? Double(totalFramesStreamed) / streamSampleRate
                            : 0
                    } else {
                        let now = Date()
                        if sessionStartDate == nil {
                            logger.warning("sessionStartDate is nil during consumeResults — using 0")
                        }
                        elapsed = sessionStartDate.map { now.timeIntervalSince($0) } ?? 0
                    }

                    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    let segment = TranscriptSegment(
                        text: trimmed,
                        startTime: lastSegmentEndTime,
                        endTime: elapsed,
                        speakerLabel: nil,
                        confidence: 1.0
                    )
                    lastSegmentEndTime = elapsed

                    onFinalSegment?(segment)
                    volatileText = ""
                } else {
                    volatileText = rawText
                }
            }
            logger.info("Recognition task completed")
        } catch {
            logger.error("Speech recognition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Stream Audio

    /// Feed a raw audio buffer from the microphone or system audio capture.
    /// The buffer is automatically converted to the format expected by SpeechAnalyzer.
    func streamAudio(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat else { return }

        // Track audio-driven timing (frame count + sample rate)
        if useAudioDrivenTiming {
            if streamSampleRate == 0 {
                streamSampleRate = buffer.format.sampleRate
            }
            totalFramesStreamed += Int64(buffer.frameLength)
        }

        do {
            let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
            let input = AnalyzerInput(buffer: converted)
            inputBuilder.yield(input)
        } catch {
            logger.error("Buffer conversion failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Finish

    /// Finalize the transcription session. Call this after stopping audio capture.
    func finish() async {
        logger.info("Finishing transcription session...")
        inputBuilder.finish()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            logger.error("Finalize failed: \(error.localizedDescription, privacy: .public)")
        }

        // Bug-6: Wait for recognizer with a timeout to prevent hang if results never terminate.
        if let task = recognizerTask {
            let timeoutTask = Task {
                try? await Task.sleep(for: AppConstants.Delays.recognizerFinalizationTimeout)
                task.cancel()
            }
            _ = await task.result
            timeoutTask.cancel()
        }
        recognizerTask = nil
        transcriber = nil
        analyzer = nil
        analyzerFormat = nil
        volatileText = ""
        downloadProgress = nil
        totalFramesStreamed = 0
        streamSampleRate = 0

        logger.info("Transcription session cleaned up")
    }

    // MARK: - Model Management

    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        logger.info("Checking model availability for locale: \(locale.identifier)")

        // Download if needed
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            logger.info("Ensuring speech model is installed...")
            downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
            logger.info("Speech model ready")
        }

        // Check supported locales
        let supportedLocales = await SpeechTranscriber.supportedLocales

        if supportedLocales.isEmpty {
            logger.warning("No supported locales found — trying fallbacks")
            for fallback in Self.fallbackLocales {
                do {
                    try await reserveLocale(fallback)
                    logger.info("Fallback locale reserved: \(fallback.identifier)")
                    return
                } catch {
                    continue
                }
            }
            throw SpeechTranscriberError.localeNotSupported
        }

        // Find a supported locale
        var localeToUse = locale
        if await !isSupported(locale: locale) {
            logger.info("Preferred locale not supported, trying fallbacks...")
            var found = false
            for fallback in Self.fallbackLocales where await isSupported(locale: fallback) {
                localeToUse = fallback
                found = true
                break
            }
            guard found else {
                throw SpeechTranscriberError.localeNotSupported
            }
        }

        try await reserveLocale(localeToUse)
    }

    // B2: Fixed — removed incorrect en-US fallback that made this always return true
    private func isSupported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        let bcp47 = locale.identifier(.bcp47)
        return supported.contains { supportedLocale in
            supportedLocale.identifier == locale.identifier
                || supportedLocale.identifier(.bcp47) == bcp47
        }
    }

    private func reserveLocale(_ locale: Locale) async throws {
        let allocated = await AssetInventory.reservedLocales
        let bcp47 = locale.identifier(.bcp47)

        if allocated.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
            return
        }

        try await AssetInventory.reserve(locale: locale)
        logger.info("Locale reserved: \(locale.identifier)")
    }
}

// MARK: - Errors

enum SpeechTranscriberError: Error, LocalizedError {
    case failedToSetup
    case invalidAudioFormat
    case localeNotSupported

    var errorDescription: String? {
        switch self {
        case .failedToSetup: "Failed to set up speech recognizer."
        case .invalidAudioFormat: "No compatible audio format found."
        case .localeNotSupported: "Selected language is not supported for transcription."
        }
    }
}
