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

    /// Where to write this session's audio so it survives a crash. Set by the caller before
    /// `startRecording()`; nil means the temporary directory, which is right for capture that has
    /// no meeting to be recovered into.
    var inProgressDirectory: URL?
    /// Stored observer token for config change notifications (block-based API requires token removal).
    private var configChangeObserver: NSObjectProtocol?
    private(set) var tempFileURL: URL?

    /// Sendable holder so the audio tap can read the latest callback dynamically.
    let audioCallback = AudioBufferCallbackHolder()

    /// Lock-protected audio level written from the audio tap thread, read by the MainActor timer.
    private let pendingAudioLevel = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// Seconds written to the mic file, accumulated on the tap thread as each buffer lands.
    ///
    /// Counted here rather than read from `AVAudioFile.length`, which the tap is concurrently
    /// writing to — reading a property of a file being appended to from another thread is a race.
    /// Accumulating seconds rather than frames also survives the sample rate changing mid-recording,
    /// which happens when the input device is switched.
    private let writtenSeconds = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

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

        // Acoustic echo cancellation, noise suppression and automatic gain, from the OS.
        //
        // The echo cancellation is the point. Without it the microphone re-hears the remote
        // participants coming out of the speakers, so every remote sentence is transcribed twice —
        // once from the system tap and once from the mic — and the diarizer is shown one person's
        // voice arriving on two channels and clusters them as two people.
        //
        // This transforms the input node itself, so the microphone audio saved for playback is
        // processed too. That is the intent: a recording without echo is the one worth keeping.
        // Enabled before the format is read, because enabling it changes that format.
        do {
            try inputNode.setVoiceProcessingEnabled(true)

            // Voice processing puts macOS into voice-chat mode, which ducks everything else so the
            // far end can be heard over it. For a meeting recorder that is backwards twice over: the
            // remote participants get quieter to listen to, and because the system-audio tap reads
            // the output, the recording of them may be quieter too. Ducking is configurable
            // separately from echo cancellation, so it is turned down to keep the one and drop the
            // other.
            inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
        } catch {
            logger.error("Voice processing unavailable, continuing raw: \(error.localizedDescription, privacy: .public)")
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat

        // Reuse an existing open file (e.g., after stopTap() from a mic-disable toggle)
        // so audio segments before and after the toggle are preserved in one file.
        // Create a new file only when starting fresh.
        if audioFile == nil {
            // A session recording into a meeting writes somewhere durable, so that a crash leaves
            // audio behind rather than a file the system was told to discard. Everything else — the
            // cross-app capture paths, which have no meeting to recover into — keeps the temporary
            // directory and the delete-on-reboot protection that goes with it.
            let directory = inProgressDirectory ?? FileManager.default.temporaryDirectory
            let fileURL = directory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("wav")
            tempFileURL = fileURL
            writtenSeconds.withLock { $0 = 0 }
            do {
                let newFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
                audioFile = newFile
            } catch {
                logger.error("Failed to create audio recording file: \(error.localizedDescription, privacy: .public)")
            }
            if inProgressDirectory == nil {
                // Sec-1: Set file protection to delete on next reboot if app crashes
                do {
                    try (fileURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
                } catch {
                    logger.error("Could not set file protection: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        installTap(on: inputNode, format: inputFormat)

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

    /// Installs the capture tap: metering, the write to disk, and the hand-off to the caller.
    ///
    /// Shared by the initial start and by the reinstall after a device change, which previously
    /// carried two copies of it and so two places for the two to drift apart.
    private func installTap(on node: AVAudioNode, format: AVAudioFormat) {
        // Capture the file by value; the callback is read dynamically via the thread-safe holder.
        let capturedFile = audioFile
        let callbackHolder = audioCallback
        let levelLock = pendingAudioLevel
        let writtenLock = writtenSeconds

        node.installTap(onBus: 0, bufferSize: AppConstants.Audio.tapBufferSize, format: format) { buffer, _ in
            // Audio level via Accelerate — written to the lock, read by the timer on the MainActor.
            let count = Int(buffer.frameLength)
            if let channelData = buffer.floatChannelData, count > 0, buffer.format.channelCount > 0 {
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(count))
                levelLock.withLock { $0 = AudioLevelNormalizer.normalize(rms) }
            }

            // Write to disk for playback, counting what actually landed.
            do {
                try capturedFile?.write(from: buffer)
                if buffer.format.sampleRate > 0 {
                    let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
                    writtenLock.withLock { $0 += seconds }
                }
            } catch {
                // Logged once — further errors repeat but are non-fatal, and recording continues.
                os_log(.error, "Audio file write failed: %{public}@", error.localizedDescription)
            }

            // Stream the audio on (dynamic — picks up callback changes made after start).
            //
            // Copied first. This buffer belongs to the engine and is valid only inside this
            // callback; the consumer reads it later, on another actor, and by then the engine has
            // reused the memory. The file written just above stays perfectly audible while
            // everything downstream sees silence — an empty transcript over a good recording.
            if let detached = buffer.detachedCopy() {
                callbackHolder.callback?(detached)
            }
        }
    }

    /// Reinstall the audio tap with the new format after a configuration change (e.g., device switch).
    private func handleConfigChange() {
        guard isRecording, let engine = audioEngine else { return }
        logger.warning("Audio engine configuration changed — reinstalling tap with new format")

        engine.inputNode.removeTap(onBus: 0)
        let newFormat = engine.inputNode.outputFormat(forBus: 0)
        recordingFormat = newFormat

        installTap(on: engine.inputNode, format: newFormat)
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

    /// Seconds of audio the mic file holds right now.
    ///
    /// This is what the playback mix reads back, and it is not elapsed time: across a mute the file
    /// stops growing while the clock does not, so only what was actually written says where the next
    /// activation begins in the file. Safe to read at any point, including while recording.
    var recordedDuration: TimeInterval {
        writtenSeconds.withLock { $0 }
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
