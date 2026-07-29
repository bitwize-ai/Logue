import AVFoundation
import Foundation
import os.log
import Speech

/// Manages real-time transcription via Apple Speech (macOS 26+).
/// Prefers `SpeechTranscriber` when the locale is supported; otherwise falls back to
/// `DictationTranscriber` (needed for languages like Russian that Speech long-form omits).
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

    private enum ActiveModule {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    private let converter = BufferConverter()
    private var activeModule: ActiveModule?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var recognizerTask: Task<Void, any Error>?
    private var reservedLocale: Locale?

    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation

    /// Tracks the end time of the last finalized segment for timestamp calculation.
    private var lastSegmentEndTime: TimeInterval = 0
    private var sessionStartDate: Date?

    /// Audio-driven timing state — frame count and sample rate from streamed buffers.
    private var totalFramesStreamed: Int64 = 0
    private var streamSampleRate: Double = 0

    /// Last-resort English Speech locales only when neither module supports the preferred locale.
    private static let englishSpeechFallbacks: [Locale] = [
        Locale(identifier: "en-US"),
        Locale(identifier: "en-GB"),
        Locale(identifier: "en"),
    ]

    // MARK: - Init

    init() {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputSequence = stream
        inputBuilder = continuation
    }

    // MARK: - Setup

    /// Set up the transcriber with the given locale and start listening for results.
    /// - Parameter locale: The locale for transcription, or `nil` to use the system preferred language.
    func setup(locale: Locale? = nil) async throws {
        let preferred = locale ?? TranscriptionLanguage.systemPreferredLocale
        logger.info("Selecting live speech module for locale: \(preferred.identifier, privacy: .public)")

        let selection = try await selectModule(for: preferred)
        try await configure(selection: selection)
        try await startAnalyzer(audioDriven: useAudioDrivenTiming)
    }

    // MARK: - Stream Audio

    /// Feed a raw audio buffer from the microphone or system audio capture.
    /// The buffer is automatically converted to the format expected by SpeechAnalyzer.
    func streamAudio(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat else { return }

        if useAudioDrivenTiming {
            if streamSampleRate == 0 {
                streamSampleRate = buffer.format.sampleRate
            }
            totalFramesStreamed += Int64(buffer.frameLength)
        }

        do {
            let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
            inputBuilder.yield(AnalyzerInput(buffer: converted))
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

        if let task = recognizerTask {
            let timeoutTask = Task {
                try? await Task.sleep(for: AppConstants.Delays.recognizerFinalizationTimeout)
                task.cancel()
            }
            _ = await task.result
            timeoutTask.cancel()
        }

        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }

        recognizerTask = nil
        activeModule = nil
        analyzer = nil
        analyzerFormat = nil
        volatileText = ""
        downloadProgress = nil
        totalFramesStreamed = 0
        streamSampleRate = 0

        logger.info("Transcription session cleaned up")
    }

    // MARK: - Module Selection

    private enum ModuleSelection {
        case speech(Locale)
        case dictation(Locale)
    }

    private func selectModule(for preferred: Locale) async throws -> ModuleSelection {
        if let speechLocale = await resolvedSpeechLocale(preferred) {
            logger.info("Using SpeechTranscriber for \(speechLocale.identifier, privacy: .public)")
            return .speech(speechLocale)
        }
        if let dictationLocale = await resolvedDictationLocale(preferred) {
            logger.info(
                "SpeechTranscriber unsupported — using DictationTranscriber for \(dictationLocale.identifier, privacy: .public)"
            )
            return .dictation(dictationLocale)
        }
        for fallback in Self.englishSpeechFallbacks {
            if let speechLocale = await resolvedSpeechLocale(fallback) {
                logger.warning(
                    "Preferred locale unsupported by Speech/Dictation — last-resort Speech \(speechLocale.identifier, privacy: .public)"
                )
                return .speech(speechLocale)
            }
        }
        throw SpeechTranscriberError.localeNotSupported
    }

    private func resolvedSpeechLocale(_ preferred: Locale) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: preferred),
           localeMatches(equivalent, in: supported)
        {
            return equivalent
        }
        if localeMatches(preferred, in: supported) {
            return preferred
        }
        return nil
    }

    private func resolvedDictationLocale(_ preferred: Locale) async -> Locale? {
        let supported = await DictationTranscriber.supportedLocales
        if let equivalent = await DictationTranscriber.supportedLocale(equivalentTo: preferred),
           localeMatches(equivalent, in: supported)
        {
            return equivalent
        }
        if localeMatches(preferred, in: supported) {
            return preferred
        }
        return nil
    }

    private func localeMatches(_ locale: Locale, in supported: [Locale]) -> Bool {
        let bcp47 = locale.identifier(.bcp47)
        return supported.contains { candidate in
            candidate.identifier == locale.identifier
                || candidate.identifier(.bcp47) == bcp47
        }
    }

    // MARK: - Configure + Start

    private func configure(selection: ModuleSelection) async throws {
        switch selection {
        case let .speech(locale):
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
            try await ensureAssets(for: module, locale: locale)
            activeModule = .speech(module)
            analyzer = SpeechAnalyzer(modules: [module])
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])

        case let .dictation(locale):
            // Explicit options: volatile live captions + frequent finals work better for meetings
            // than the short phrase presets. farField helps when capturing room / system audio.
            let module = DictationTranscriber(
                locale: locale,
                contentHints: [.farField],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: [.audioTimeRange]
            )
            try await ensureAssets(for: module, locale: locale)
            activeModule = .dictation(module)
            analyzer = SpeechAnalyzer(modules: [module])
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        }

        guard analyzerFormat != nil else {
            logger.error("No compatible audio format found")
            throw SpeechTranscriberError.invalidAudioFormat
        }

        sessionStartDate = Date()
        lastSegmentEndTime = 0
    }

    private func startAnalyzer(audioDriven: Bool) async throws {
        recognizerTask?.cancel()
        recognizerTask = Task {
            await self.consumeActiveModuleResults(audioDriven: audioDriven)
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
            logger.info("SpeechAnalyzer started successfully")
        } catch {
            recognizerTask?.cancel()
            _ = await recognizerTask?.result
            recognizerTask = nil
            activeModule = nil
            analyzer = nil
            analyzerFormat = nil
            logger.error("Failed to start SpeechAnalyzer: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Results

    private func consumeActiveModuleResults(audioDriven: Bool) async {
        switch activeModule {
        case let .speech(module):
            await consumeSpeechResults(from: module, audioDriven: audioDriven)
        case let .dictation(module):
            await consumeDictationResults(from: module, audioDriven: audioDriven)
        case nil:
            logger.error("No active speech module when starting result consumption")
        }
    }

    private func consumeSpeechResults(from module: SpeechTranscriber, audioDriven: Bool) async {
        do {
            for try await result in module.results {
                handleRecognitionText(
                    String(result.text.characters),
                    isFinal: result.isFinal,
                    audioDriven: audioDriven
                )
            }
            logger.info("SpeechTranscriber recognition completed")
        } catch {
            logger.error("SpeechTranscriber recognition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func consumeDictationResults(from module: DictationTranscriber, audioDriven: Bool) async {
        do {
            for try await result in module.results {
                handleRecognitionText(
                    String(result.text.characters),
                    isFinal: result.isFinal,
                    audioDriven: audioDriven
                )
            }
            logger.info("DictationTranscriber recognition completed")
        } catch {
            logger.error("DictationTranscriber recognition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleRecognitionText(_ rawText: String, isFinal: Bool, audioDriven: Bool) {
        if isFinal {
            let elapsed = currentElapsedTime(audioDriven: audioDriven)
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

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

    private func currentElapsedTime(audioDriven: Bool) -> TimeInterval {
        if audioDriven {
            return streamSampleRate > 0
                ? Double(totalFramesStreamed) / streamSampleRate
                : 0
        }
        if sessionStartDate == nil {
            logger.warning("sessionStartDate is nil during recognition — using 0")
        }
        return sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    // MARK: - Model Management

    private func ensureAssets(for module: any SpeechModule, locale: Locale) async throws {
        logger.info("Checking model availability for locale: \(locale.identifier)")

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            logger.info("Ensuring speech model is installed...")
            downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
            logger.info("Speech model ready")
        }

        try await reserveLocale(locale)
    }

    private func reserveLocale(_ locale: Locale) async throws {
        let allocated = await AssetInventory.reservedLocales
        let bcp47 = locale.identifier(.bcp47)

        if allocated.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
            reservedLocale = locale
            return
        }

        try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale
        logger.info("Locale reserved: \(locale.identifier)")
    }
}

// MARK: - Errors

enum SpeechTranscriberError: Error, LocalizedError {
    case invalidAudioFormat
    case localeNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidAudioFormat: "No compatible audio format found."
        case .localeNotSupported: "Selected language is not supported for transcription."
        }
    }
}
