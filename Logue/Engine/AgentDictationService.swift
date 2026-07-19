import AVFoundation
import Foundation
import os.log
import Speech

/// One-shot speech-to-text dictation for the agent input bar. Uses
/// `SFSpeechRecognizer` against a tap on `AVAudioEngine`'s input — a strict
/// subset of the meeting recorder's pipeline, intentionally lighter so it
/// won't fight with `RecordingSessionManager` for the mic.
///
/// Flow:
/// 1. `start()` requests speech + mic authorization (no-op if already granted),
///    boots an `AVAudioEngine` tap, and pipes buffers into a recognition request.
/// 2. As partial transcripts arrive, `onTranscript` fires on the main actor.
/// 3. `stop()` ends the audio tap + recognition request and resolves the final
///    transcript via `onTranscript`.
@Observable
@MainActor
final class AgentDictationService {
    static let shared = AgentDictationService()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AgentDictation")

    /// True while audio is being captured.
    private(set) var isRecording = false
    /// Latest interim transcript (live caption while the user is speaking).
    private(set) var currentTranscript: String = ""
    /// Last error surfaced to the UI; cleared on next `start()`.
    private(set) var lastError: String?

    /// Callback fired on every partial / final transcript update.
    /// `isFinal` is true once the underlying recognizer marks the result final
    /// (also set true by `stop()`).
    var onTranscript: (@MainActor @Sendable (String, _ isFinal: Bool) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Increments on every `start()`. The recognition callback captures the
    /// generation number it was created for and ignores results when the
    /// service has already moved on (e.g. teardown happened, or user started
    /// a new dictation in rapid succession).
    private var generation = 0

    private init() {}

    // MARK: - Public

    /// Begin dictation. Resolves to `true` if recording started, `false` if any
    /// permission or hardware issue prevented it. UI should disable the mic
    /// button when this returns `false` and surface `lastError`.
    @discardableResult
    func start() async -> Bool {
        guard !isRecording else { return true }
        lastError = nil
        currentTranscript = ""

        guard recognizer?.isAvailable == true else {
            lastError = "Speech recognition is unavailable on this device."
            return false
        }

        // Speech authorization. Re-check state after the await — Swift Concurrency
        // can suspend between resume and use.
        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            lastError = "Speech recognition permission was not granted."
            return false
        }
        guard !isRecording else { return true }

        do {
            try startEngineLocked()
            isRecording = true
            return true
        } catch {
            lastError = "Could not start dictation: \(error.localizedDescription)"
            logger.error("Dictation start failed: \(error.localizedDescription, privacy: .public)")
            tearDown()
            return false
        }
    }

    /// Stop dictation. Resolves the recognition task and triggers a final
    /// `onTranscript` callback with whatever was captured.
    func stop() {
        guard isRecording else { return }
        let final = currentTranscript
        tearDown()
        isRecording = false
        onTranscript?(final, true)
    }

    // MARK: - Engine lifecycle

    private func startEngineLocked() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Force on-device recognition where supported. Falls back to server
        // automatically if the language pack is missing — but we tell the user
        // up front this is local-first.
        if let recognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Recognition task — fires on a background queue. Hop to MainActor
        // before mutating any service state. Each callback carries the
        // generation it was created for and bails if the service has moved
        // on (teardown / rapid restart) — without this guard, a late callback
        // can clobber `currentTranscript` after the UI has already finalized
        // a different session.
        generation += 1
        let myGeneration = generation
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == myGeneration else { return }
                if let result {
                    currentTranscript = result.bestTranscription.formattedString
                    onTranscript?(currentTranscript, result.isFinal)
                    if result.isFinal {
                        tearDown()
                        isRecording = false
                    }
                }
                if let error {
                    logger.debug(
                        "Recognition task error: \(error.localizedDescription, privacy: .public)"
                    )
                    // No-op for "no speech" / cancellation — `stop()` already
                    // surfaced what we had. Don't overwrite a successful final.
                }
            }
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: AppConstants.Audio.tapBufferSize,
            format: inputFormat
        ) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        self.request = request
    }

    private func tearDown() {
        // Bump generation FIRST so any callback already queued behind us hops
        // onto the main actor, sees a stale generation, and exits early.
        generation += 1
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        request?.endAudio()
        task?.cancel()
        audioEngine = nil
        request = nil
        task = nil
    }

    // MARK: - Auth

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }
}
