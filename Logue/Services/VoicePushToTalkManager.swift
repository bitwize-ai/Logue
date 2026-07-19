import AVFoundation
import Foundation
import os.log
import Speech

/// Manages push-to-talk voice input for AI chat panels.
/// Users can tap the mic button or hold Right Option to speak;
/// releasing delivers the transcribed text to the active chat panel.
@Observable
@MainActor
final class VoicePushToTalkManager {
    static let shared = VoicePushToTalkManager()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "VoicePTT")

    // MARK: - Public State

    var isRecording = false
    var partialTranscript = ""
    var audioLevel: Float = 0
    var errorMessage: String?

    // MARK: - Callback

    /// Set by the active chat panel to receive the final transcript.
    var onTranscriptReady: ((String) -> Void)?

    // MARK: - Internals

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var finalTranscript = ""

    private init() {}

    // MARK: - Start / Stop

    func startListening() {
        guard !isRecording else { return }

        // Don't conflict with an active meeting recording
        if RecordingSessionManager.shared.isRecording {
            errorMessage = "Microphone is in use by an active recording."
            logger.warning("Push-to-talk blocked — meeting recording active")
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available."
            logger.warning("Speech recognizer unavailable")
            return
        }

        errorMessage = nil
        partialTranscript = ""
        finalTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        installAudioTap(on: inputNode, format: recordingFormat, request: request)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalTranscript = result.bestTranscription.formattedString
                    }
                }

                if let error {
                    let nsError = error as NSError
                    // 216 = recognition cancelled (normal), 1110 = no speech detected
                    if nsError.code != 216, nsError.code != 1110 {
                        self.logger.warning("Recognition error: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            isRecording = true
            logger.info("Push-to-talk recording started")
        } catch {
            inputNode.removeTap(onBus: 0)
            logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to start microphone."
            cleanup()
        }
    }

    // B5: Track delay task to prevent race on quick toggle
    private var stopDelayTask: Task<Void, Never>?

    func stopListening() {
        guard isRecording else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        isRecording = false
        audioLevel = 0

        stopDelayTask?.cancel()
        stopDelayTask = Task { [weak self] in
            // Brief pause to let recognition finalize
            try? await Task.sleep(for: AppConstants.Delays.voiceRecognitionFinalize)
            guard !Task.isCancelled, let self else { return }

            let transcript = finalTranscript.isEmpty ? partialTranscript : finalTranscript
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty {
                onTranscriptReady?(trimmed)
                logger.info("Push-to-talk delivered transcript (\(trimmed.count, privacy: .public) chars)")
            } else {
                logger.info("Push-to-talk: no speech detected")
            }

            partialTranscript = ""
            finalTranscript = ""
            cleanup()
        }
    }

    /// Toggle recording — convenience for mic button taps.
    func toggle() {
        if isRecording {
            stopListening()
        } else {
            startListening()
        }
    }

    // MARK: - Permissions

    /// Returns true if both microphone and speech recognition are authorized.
    func checkPermissions() async -> Bool {
        let micGranted = await checkMicrophonePermission()
        let speechGranted = await checkSpeechPermission()
        return micGranted && speechGranted
    }

    private func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func checkSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
        default:
            return false
        }
    }

    // MARK: - Audio Tap

    private func installAudioTap(on inputNode: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)

            if let channelData = buffer.floatChannelData {
                let samples = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
                let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / max(Float(samples.count), 1))
                let normalized = AudioLevelNormalizer.normalize(rms)
                Task { @MainActor in
                    self?.audioLevel = normalized
                }
            }
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        audioLevel = 0
    }
}
