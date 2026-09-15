import AVFoundation
import Foundation
import os.log
import Speech

/// Live captions via Apple's SpeechAnalyzer. Prefers the new SpeechTranscriber
/// model; falls back to DictationTranscriber when that model cannot be installed
/// (German currently fails as `transcription.de` / Not Installing).
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
        recognizerTask != nil || legacyTask != nil
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
    private var liveCaption: LiveCaptionModule?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var recognizerTask: Task<Void, any Error>?
    private var legacyRecognizer: SFSpeechRecognizer?
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?

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

    /// Locales whose SpeechAnalyzer path already failed this process. Retrying it on the
    /// next meeting only races a half-torn-down analyzer against the system recognizer.
    private static var analyzerFailedLanguages = Set<String>()

    /// Callbacks from a cancelled recognition task must not restart capture or emit
    /// duplicate finals after `finish()` has moved on.
    private var recognitionGeneration = 0
    private var isFinishing = false
    private var legacyFinishWaiter: CheckedContinuation<Void, Never>?

    /// Set up the transcriber with the given locale and start listening for results.
    /// - Parameters:
    ///   - locale: Locale for live ASR. `nil` uses `Locale.current` (Mac language), not en-US.
    ///   - allowLanguageFallback: When true (Auto), English locales may be used if the
    ///     requested language has no Speech model. When false, a missing language fails.
    func setup(locale: Locale? = nil, allowLanguageFallback: Bool = true) async throws {
        let requestedLocale = locale ?? Locale.current
        logger.info("Setting up live captions for locale: \(requestedLocale.identifier)")
        let languageKey = requestedLocale.language.languageCode?.identifier ?? requestedLocale.identifier

        if Self.analyzerFailedLanguages.contains(languageKey) {
            logger.info("Skipping SpeechAnalyzer for \(languageKey) — it already failed this session")
            try setupLegacyRecognizer(locale: requestedLocale)
            return
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    try await self.setupAnalyzer(
                        requested: requestedLocale,
                        allowLanguageFallback: allowLanguageFallback
                    )
                }
                group.addTask {
                    try await Task.sleep(for: AppConstants.Delays.speechAssetDownloadTimeout)
                    throw SpeechTranscriberError.assetInstallFailed(
                        locale: requestedLocale.identifier,
                        underlying: "Timed out waiting for the speech model."
                    )
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            Self.analyzerFailedLanguages.insert(languageKey)
            logger.error(
                "SpeechAnalyzer unavailable: \(error.localizedDescription, privacy: .public); using system speech recognizer"
            )
            try setupLegacyRecognizer(locale: requestedLocale)
        }
    }

    @MainActor
    private func consumeCaption(_ caption: LiveCaptionModule, audioDriven: Bool) async {
        switch caption {
        case let .speech(transcriber):
            await consumeSpeech(transcriber, audioDriven: audioDriven)
        case let .dictation(transcriber):
            await consumeDictation(transcriber, audioDriven: audioDriven)
        }
    }

    @MainActor
    private func consumeSpeech(_ transcriber: SpeechTranscriber, audioDriven: Bool) async {
        do {
            for try await result in transcriber.results {
                applyCaption(text: String(result.text.characters), isFinal: result.isFinal, audioDriven: audioDriven)
            }
            logger.info("Recognition task completed")
        } catch {
            logger.error("Speech recognition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func consumeDictation(_ transcriber: DictationTranscriber, audioDriven: Bool) async {
        do {
            for try await result in transcriber.results {
                applyCaption(text: String(result.text.characters), isFinal: result.isFinal, audioDriven: audioDriven)
            }
            logger.info("Recognition task completed")
        } catch {
            logger.error("Speech recognition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func applyCaption(text rawText: String, isFinal: Bool, audioDriven: Bool) {
        if isFinal {
            let elapsed: TimeInterval
            if audioDriven {
                elapsed = streamSampleRate > 0
                    ? Double(totalFramesStreamed) / streamSampleRate
                    : 0
            } else {
                if sessionStartDate == nil {
                    logger.warning("sessionStartDate is nil during consumeResults — using 0")
                }
                elapsed = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
            }

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

    // MARK: - Stream Audio

    /// Feed a raw audio buffer from the microphone or system audio capture.
    /// The buffer is automatically converted to the format expected by SpeechAnalyzer.
    func streamAudio(_ buffer: AVAudioPCMBuffer) {
        if let legacyRequest {
            legacyRequest.append(buffer)
            return
        }
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
        isFinishing = true
        await finishLegacyRecognizer()
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
        flushVolatileCaption()
        recognitionGeneration += 1
        recognizerTask = nil
        liveCaption = nil
        analyzer = nil
        analyzerFormat = nil
        volatileText = ""
        downloadProgress = nil
        totalFramesStreamed = 0
        streamSampleRate = 0
        isFinishing = false

        logger.info("Transcription session cleaned up")
    }

    /// The system recognizer often keeps the whole utterance as a partial until audio ends.
    /// Clearing `volatileText` without emitting it is how a meeting can show captions live
    /// and save an empty transcript.
    fileprivate func flushVolatileCaption() {
        let leftover = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftover.isEmpty else { return }
        applyCaption(text: leftover, isFinal: true, audioDriven: useAudioDrivenTiming)
    }
}

// MARK: - Live caption modules

private enum LiveCaptionModule {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var module: any SpeechModule {
        switch self {
        case let .speech(transcriber): transcriber
        case let .dictation(transcriber): transcriber
        }
    }
}

// MARK: - Model Management

extension SpeechTranscriberEngine {
    fileprivate func setupAnalyzer(
        requested: Locale,
        allowLanguageFallback: Bool
    ) async throws {
        let caption = try await makeLiveCaption(
            requested: requested,
            allowLanguageFallback: allowLanguageFallback
        )
        liveCaption = caption

        analyzer = SpeechAnalyzer(modules: [caption.module])
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [caption.module]
        )

        guard let format = analyzerFormat else {
            logger.error("No compatible audio format found")
            throw SpeechTranscriberError.invalidAudioFormat
        }

        sessionStartDate = Date()
        lastSegmentEndTime = 0

        recognizerTask?.cancel()
        let audioDriven = useAudioDrivenTiming
        recognizerTask = Task {
            await self.consumeCaption(caption, audioDriven: audioDriven)
        }

        do {
            try await analyzer?.prepareToAnalyze(in: format)
            try await analyzer?.start(inputSequence: inputSequence)
            logger.info("SpeechAnalyzer started successfully")
        } catch {
            recognizerTask?.cancel()
            _ = await recognizerTask?.result
            recognizerTask = nil
            liveCaption = nil
            analyzer = nil
            analyzerFormat = nil
            logger.error("Failed to start SpeechAnalyzer: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    fileprivate func makeLiveCaption(
        requested: Locale,
        allowLanguageFallback: Bool
    ) async throws -> LiveCaptionModule {
        logger.info("Checking model availability for locale: \(requested.identifier)")

        if let speech = await readySpeechTranscriber(requested: requested) {
            logger.info("Using installed SpeechTranscriber for \(requested.identifier)")
            return .speech(speech)
        }
        if let dictation = await readyDictationTranscriber(requested: requested) {
            logger.info("Using installed DictationTranscriber for \(requested.identifier)")
            return .dictation(dictation)
        }
        if allowLanguageFallback, let fallback = await englishCaption() {
            logger.info("Fell back to English live captions")
            return fallback
        }

        throw SpeechTranscriberError.assetInstallFailed(
            locale: requested.identifier,
            underlying: "No installed live-caption model for this language."
        )
    }

    fileprivate func readySpeechTranscriber(requested: Locale) async -> SpeechTranscriber? {
        let installed = await SpeechTranscriber.installedLocales
        guard let locale = TranscriptionLanguage.matchingLocale(for: requested, in: installed) else {
            return nil
        }
        do {
            try await reserveLocale(locale)
            let transcriber = makeSpeechTranscriber(locale: locale)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                logger.info("SpeechTranscriber lists \(locale.identifier) but the asset is not installed")
                return nil
            }
            return transcriber
        } catch {
            logger.error("Could not reserve SpeechTranscriber locale \(locale.identifier): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    fileprivate func readyDictationTranscriber(requested: Locale) async -> DictationTranscriber? {
        let installed = await DictationTranscriber.installedLocales
        guard let locale = TranscriptionLanguage.matchingLocale(for: requested, in: installed) else {
            return nil
        }
        do {
            try await reserveLocale(locale)
            let transcriber = makeDictationTranscriber(locale: locale)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                logger.info("DictationTranscriber lists \(locale.identifier) but the asset is not installed")
                return nil
            }
            return transcriber
        } catch {
            logger.error("Could not reserve DictationTranscriber locale \(locale.identifier): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    fileprivate func englishCaption() async -> LiveCaptionModule? {
        for fallback in Self.fallbackLocales {
            if let speech = await readySpeechTranscriber(requested: fallback) {
                return .speech(speech)
            }
            if let dictation = await readyDictationTranscriber(requested: fallback) {
                return .dictation(dictation)
            }
        }
        return nil
    }

    fileprivate func makeSpeechTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
    }

    fileprivate func makeDictationTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    }

    fileprivate func reserveLocale(_ locale: Locale) async throws {
        let allocated = await AssetInventory.reservedLocales
        let bcp47 = locale.identifier(.bcp47)

        if allocated.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
            return
        }

        if allocated.count >= AssetInventory.maximumReservedLocales, let oldest = allocated.first {
            logger.info("Releasing reserved locale \(oldest.identifier) to make room")
            await AssetInventory.release(reservedLocale: oldest)
        }

        try await AssetInventory.reserve(locale: locale)
        logger.info("Locale reserved: \(locale.identifier)")
    }
}

// MARK: - System speech recognizer (macOS dictation models)

extension SpeechTranscriberEngine {
    fileprivate func setupLegacyRecognizer(locale: Locale) throws {
        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
            ?? SFSpeechRecognizer()
        guard let recognizer else {
            throw SpeechTranscriberError.localeNotSupported
        }

        let request = makeLegacyRequest(recognizer: recognizer)

        sessionStartDate = Date()
        lastSegmentEndTime = 0
        isFinishing = false
        legacyRecognizer = recognizer
        legacyRequest = request
        startLegacyTask(recognizer: recognizer, request: request)
        logger.info("System speech recognizer started for \(locale.identifier)")
    }

    fileprivate func makeLegacyRequest(recognizer: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return request
    }

    fileprivate func startLegacyTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        recognitionGeneration += 1
        let generation = recognitionGeneration
        legacyTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleLegacyResult(result, error: error, generation: generation)
            }
        }
    }

    fileprivate func handleLegacyResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        generation: Int
    ) {
        guard generation == recognitionGeneration else { return }
        if let result {
            applyCaption(
                text: result.bestTranscription.formattedString,
                isFinal: result.isFinal,
                audioDriven: false
            )
            if result.isFinal {
                if isFinishing {
                    completeLegacyFinishWait()
                } else {
                    restartLegacyRecognition()
                }
            }
            return
        }
        if let error {
            if isFinishing {
                completeLegacyFinishWait()
                return
            }
            logger.error("System speech recognizer error: \(error.localizedDescription, privacy: .public)")
            restartLegacyRecognition()
        }
    }

    fileprivate func restartLegacyRecognition() {
        guard !isFinishing, let recognizer = legacyRecognizer else { return }
        legacyRequest?.endAudio()
        legacyTask?.cancel()
        let request = makeLegacyRequest(recognizer: recognizer)
        legacyRequest = request
        startLegacyTask(recognizer: recognizer, request: request)
    }

    fileprivate func finishLegacyRecognizer() async {
        guard legacyRequest != nil || legacyTask != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            legacyFinishWaiter = continuation
            legacyRequest?.endAudio()
            Task { @MainActor in
                try? await Task.sleep(for: AppConstants.Delays.legacyRecognizerFinalTimeout)
                self.completeLegacyFinishWait()
            }
        }
        recognitionGeneration += 1
        legacyTask?.cancel()
        legacyTask = nil
        legacyRequest = nil
        legacyRecognizer = nil
    }

    fileprivate func completeLegacyFinishWait() {
        guard let waiter = legacyFinishWaiter else { return }
        legacyFinishWaiter = nil
        waiter.resume()
    }
}

// MARK: - Errors

enum SpeechTranscriberError: Error, LocalizedError {
    case failedToSetup
    case invalidAudioFormat
    case localeNotSupported
    case assetInstallFailed(locale: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .failedToSetup: "Failed to set up speech recognizer."
        case .invalidAudioFormat: "No compatible audio format found."
        case .localeNotSupported: "Selected language is not supported for transcription."
        case let .assetInstallFailed(locale, underlying):
            "Couldn't install the \(locale) live-caption model. Check the network and try Start again. (\(underlying))"
        }
    }
}
