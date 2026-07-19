import Accelerate
import AVFoundation
import Foundation
import os.log

/// Captures audio from the Mac's microphone using AVAudioEngine.
/// Streams raw AVAudioPCMBuffer to the caller — no chunking or format conversion.
@Observable
@MainActor
final class AudioRecorder {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AudioRecorder")

    // MARK: - State

    var isRecording = false
    var currentTime: TimeInterval = 0
    var audioLevel: Float = 0

    /// The audio format of the mic input. Available after `startRecording()` succeeds.
    private(set) var recordingFormat: AVAudioFormat?

    // MARK: - Internals

    private var audioEngine: AVAudioEngine?
    /// Thread-safe timer storage — accessed from @MainActor (scheduledTimer) and nonisolated deinit.
    private let timerLock = OSAllocatedUnfairLock<Timer?>(initialState: nil)
    private var startTime: Date?
    private var audioFile: AVAudioFile?
    /// Stored observer token for config change notifications (block-based API requires token removal).
    private var configChangeObserver: NSObjectProtocol?
    private(set) var tempFileURL: URL?

    /// Sendable holder so the audio tap can read the latest callback dynamically.
    let audioCallback = AudioBufferCallbackHolder()

    /// Lock-protected audio level written from the audio tap thread, read by the MainActor timer.
    private let pendingAudioLevel = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// Callback fired with every raw audio buffer from the microphone tap.
    /// Updating this after recording starts takes effect immediately (dynamic dispatch).
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioCallback.callback }
        set { audioCallback.callback = newValue }
    }

    deinit {
        // Timer.invalidate() must be called on the same thread that created the timer (MainActor).
        // deinit may run on an arbitrary thread, so schedule the invalidation on the main run loop.
        let timer = timerLock.withLock { lock -> Timer? in
            let existing = lock; lock = nil; return existing
        }
        if let timer {
            RunLoop.main.perform { timer.invalidate() }
        }
    }

    // MARK: - Recording Control

    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat

        // Reuse an existing open file (e.g., after stopTap() from a mic-disable toggle)
        // so audio segments before and after the toggle are preserved in one file.
        // Create a new file only when starting fresh.
        if audioFile == nil {
            let fileURL = FileManager.default.temporaryDirectory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("wav")
            tempFileURL = fileURL
            do {
                let newFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
                audioFile = newFile
            } catch {
                logger.error("Failed to create audio recording file: \(error.localizedDescription, privacy: .public)")
            }
            // Sec-1: Set file protection to delete on next reboot if app crashes
            try? (fileURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        }

        // Capture file by value; callback is read dynamically via thread-safe holder
        let capturedFile = audioFile
        let callbackHolder = audioCallback

        let levelLock = pendingAudioLevel
        inputNode.installTap(onBus: 0, bufferSize: AppConstants.Audio.tapBufferSize, format: inputFormat) { buffer, _ in
            // Calculate audio level via Accelerate (written to lock, read by timer on MainActor)
            let count = Int(buffer.frameLength)
            if let channelData = buffer.floatChannelData, count > 0, buffer.format.channelCount > 0 {
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(count))
                let normalized = AudioLevelNormalizer.normalize(rms)
                levelLock.withLock { $0 = normalized }
            }

            // Write to disk for playback
            do {
                try capturedFile?.write(from: buffer)
            } catch {
                // Log once — further errors will repeat but are non-fatal (recording continues)
                os_log(.error, "Audio file write failed: %{public}@", error.localizedDescription)
            }

            // Stream raw buffer to caller (dynamic — picks up callback changes after start)
            callbackHolder.callback?(buffer)
        }

        try engine.start()
        // Observe audio configuration changes (e.g., device disconnected, Bluetooth switch).
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigChange() }
        }

        audioEngine = engine
        isRecording = true
        startTime = Date()

        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.currentTime = Date().timeIntervalSince(start)
                self.audioLevel = self.pendingAudioLevel.withLock { $0 }
            }
        }
        timerLock.withLock { $0 = newTimer }

        logger.info("Microphone recording started")
    }

    /// Reinstall the audio tap with the new format after a configuration change (e.g., device switch).
    private func handleConfigChange() {
        guard isRecording, let engine = audioEngine else { return }
        logger.warning("Audio engine configuration changed — reinstalling tap with new format")

        engine.inputNode.removeTap(onBus: 0)
        let newFormat = engine.inputNode.outputFormat(forBus: 0)
        recordingFormat = newFormat

        let capturedFile = audioFile
        let callbackHolder = audioCallback
        let levelLock = pendingAudioLevel
        engine.inputNode.installTap(onBus: 0, bufferSize: AppConstants.Audio.tapBufferSize, format: newFormat) { buffer, _ in
            let count = Int(buffer.frameLength)
            if let channelData = buffer.floatChannelData, count > 0, buffer.format.channelCount > 0 {
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(count))
                let normalized = AudioLevelNormalizer.normalize(rms)
                levelLock.withLock { $0 = normalized }
            }
            do {
                try capturedFile?.write(from: buffer)
            } catch {
                os_log(.error, "Audio file write failed in config change handler: %{public}@", error.localizedDescription)
            }
            callbackHolder.callback?(buffer)
        }
        do {
            try engine.start()
        } catch {
            logger.error("Audio engine restart failed after config change: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops the engine and tap without closing the audio file.
    /// Use when the mic is temporarily toggled off so a subsequent `startRecording()` can
    /// continue appending to the same file instead of creating a new one.
    func stopTap() {
        guard isRecording else { return }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        recordingFormat = nil
        timerLock.withLock { $0?.invalidate(); $0 = nil }
        startTime = nil
        audioLevel = 0
        // audioFile intentionally left open — caller will call startRecording() to resume
        // or stopRecording() to finalize
        logger.info("Microphone tap paused (file kept open)")
    }

    func stopRecording() {
        // Stop the engine/tap only if still running (may already be stopped via stopTap())
        if isRecording {
            if let observer = configChangeObserver {
                NotificationCenter.default.removeObserver(observer)
                configChangeObserver = nil
            }
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            isRecording = false
            recordingFormat = nil
            timerLock.withLock { $0?.invalidate(); $0 = nil }
            startTime = nil
            audioLevel = 0
        }
        // Always finalize and close the file, even if the engine was already stopped via stopTap()
        audioFile = nil
        // tempFileURL is preserved — caller is responsible for consuming or clearing it
        logger.info("Microphone recording stopped")
    }

    /// Deletes the temporary WAV file and clears the URL. Call after the file has been
    /// moved to permanent storage (or if no permanent copy is needed).
    func clearTemporaryFile() {
        guard let url = tempFileURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to delete temp audio file: \(error.localizedDescription, privacy: .public)")
        }
        tempFileURL = nil
    }
}
