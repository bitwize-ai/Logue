import AppKit
import AVFoundation
import FluidAudio
import Foundation
import os.log

/// Typed errors for recording failures — replaces raw String error messages.
enum RecordingError: LocalizedError {
    case micPermissionDenied
    case systemAudioPermissionDenied
    case micStartFailed(String)
    case systemAudioStartFailed(String)
    case speechEngineSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            "Microphone access denied. Grant permission in System Settings > Privacy > Microphone."
        case .systemAudioPermissionDenied:
            "System audio permission required. Grant permission in System Settings > Privacy & Security > System Audio Recording."
        case let .micStartFailed(detail):
            "Failed to start microphone: \(detail)"
        case let .systemAudioStartFailed(detail):
            "Failed to start system audio capture: \(detail)"
        case let .speechEngineSetupFailed(detail):
            "Failed to set up speech recognition: \(detail)"
        }
    }
}

/// Manages the lifecycle of a recording session, surviving SwiftUI view recreation.
/// Owns AudioRecorder, SystemAudioCapture, SpeechTranscriberEngine, and DiarizationManager.
/// Audio buffers stream directly to Apple's SpeechTranscriber — no chunking or backpressure needed.
/// After recording stops, FluidAudio performs speaker diarization on accumulated audio.
/// Cohesive recording state machine (start/stop + mid-recording mic/system-audio toggles).
/// Splitting into extensions would require widening ~20 private members to internal, which
/// weakens encapsulation more than it helps; kept as one unit.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class RecordingSessionManager {
    static let shared = RecordingSessionManager()
    private init() {
        // Pre-warm all diarization models silently at app launch so the first
        // recording session doesn't pay the model-download cost.
        Task { await DiarizationManager.prewarmGlobalCache() }
    }

    let logger = Logger(subsystem: AppConstants.bundleID, category: "RecordingSession")

    // MARK: - State

    enum RecordingState: Equatable {
        case idle
        case starting
        case recording
        case stopping
    }

    var recordingState: RecordingState = .idle

    var isRecording: Bool {
        recordingState == .recording
    }

    var isStartingRecording: Bool {
        recordingState == .starting
    }

    var isStopping: Bool {
        recordingState == .stopping
    }

    var currentMeetingID: UUID?
    var errorMessage: String?
    var isDiarizing = false
    /// Human-readable label for the current post-recording diarization stage. Empty when idle.
    var diarizationStage = ""
    /// Status of speaker detection during recording.
    var speakerDetectionStatus: SpeakerDetectionStatus = .inactive

    enum SpeakerDetectionStatus: Equatable {
        case inactive
        case downloadingModels
        case active
        case unavailable
    }

    var isCapturingSystemAudio = false
    var isMicActive = false
    var isPeriodicDiarizationStopped = false
    var hasPeriodicDiarizationResults = false
    private var postRecordingTask: Task<Void, Never>?
    private var diarizationInitTask: Task<Void, Never>?

    /// Handles AI title/summary/space-suggestion after recording stops.
    let postRecordingPipeline = PostRecordingPipeline()

    /// Current volatile transcription text (in-progress, not yet finalized).
    /// In online meeting mode, prioritizes mic text (lower latency) when both engines are active.
    var volatileText: String {
        let systemText = speechEngine?.volatileText ?? ""
        let micText = micSpeechEngine?.volatileText ?? ""
        if !micText.isEmpty {
            return micText
        }
        return systemText
    }

    // MARK: - Engines

    let audioRecorder = AudioRecorder()
    let systemCapture = SystemAudioCapture()
    private var speechEngine: SpeechTranscriberEngine?
    /// Second speech engine for real-time mic transcription during online meetings.
    private var micSpeechEngine: SpeechTranscriberEngine?
    private var diarizationManager: DiarizationManager?

    private var recordingLocale: Locale?

    /// Time offset applied when continuing recording on a meeting that already has segments.
    /// New segment timestamps and elapsed time are shifted forward by this amount.
    private var timeOffset: TimeInterval = 0

    /// Open AVAudioFile for writing system audio in online meeting mode.
    /// Kept open during recording; set to nil in teardownAudioPipeline() to flush and close it.
    private var systemAudioFile: AVAudioFile?
    /// Temp path for the system audio recording file. Preserved after teardown so stopRecording() can move it.
    private var systemAudioTempURL: URL?

    // MARK: - Audio Buffer Stream

    /// Single-consumer stream that coalesces audio buffers from the audio thread.
    /// Replaces per-buffer `Task { @MainActor }` creation to prevent MainActor flooding.
    private var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var audioBufferConsumerTask: Task<Void, Never>?
    /// Separate stream for mic-only buffers when a dedicated mic engine is active (in-person enableMic).
    private var micBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var micBufferConsumerTask: Task<Void, Never>?

    // MARK: - Computed

    var elapsedTime: TimeInterval {
        guard let meetingID = currentMeetingID else { return 0 }
        let mode = MeetingStore.shared.meetings.first { $0.id == meetingID }?.recordingMode ?? .inPerson
        let rawTime: TimeInterval = switch mode {
        case .inPerson, .voiceNote: audioRecorder.currentTime
        case .onlineMeeting: systemCapture.currentTime
        }
        return rawTime + timeOffset
    }

    var audioLevel: Float {
        guard let meetingID = currentMeetingID else { return 0 }
        let mode = MeetingStore.shared.meetings.first { $0.id == meetingID }?.recordingMode ?? .inPerson
        switch mode {
        case .inPerson, .voiceNote: return audioRecorder.audioLevel
        case .onlineMeeting: return max(systemCapture.audioLevel, audioRecorder.audioLevel)
        }
    }

    // MARK: - Start Recording

    // swiftlint:disable:next function_body_length
    func startRecording(for meeting: MeetingNote) async {
        guard recordingState == .idle else { return }
        recordingState = .starting
        errorMessage = nil

        // Check microphone permission FIRST — before any heavy setup or waiting
        // This ensures the OS permission dialog appears immediately on first use
        let needsMic = meeting.recordingMode != .onlineMeeting
        if needsMic {
            let hasPermission = await checkMicrophonePermission()
            guard hasPermission else {
                errorMessage = RecordingError.micPermissionDenied.localizedDescription
                recordingState = .idle
                return
            }
        }

        // Wait for previous post-recording tasks to complete (max 5s) before starting new session
        if let task = postRecordingTask {
            logger.info("Waiting for previous post-recording task to complete before resume...")
            let didFinish = await withTaskGroup(of: Bool.self) { group in
                group.addTask { await task.value; return true }
                group.addTask { try? await Task.sleep(for: AppConstants.Delays.postRecordingWaitTimeout); return false }
                return await group.next() ?? false
            }
            if !didFinish {
                task.cancel()
                _ = await task.value // Wait for actual cancellation to complete
                logger.warning("Post-recording task timed out — cancelled and awaited")
            }
            postRecordingTask = nil
        }
        postRecordingPipeline.cancel()

        currentMeetingID = meeting.id
        let meetingID = meeting.id

        // Calculate time offset if meeting already has segments (continuing a recording)
        if let lastEnd = meeting.segments.map(\.endTime).max(), lastEnd > 0 {
            // Add a small gap (1s) between previous and new content
            timeOffset = lastEnd + 1.0
        } else {
            timeOffset = 0
        }
        let offset = timeOffset

        // Set up the speech transcriber engine
        let isOnlineMeeting = meeting.recordingMode == .onlineMeeting
        let engine = SpeechTranscriberEngine()
        // C3: Explicitly annotate as @MainActor for Sendable safety
        engine.onFinalSegment = { @MainActor segment in
            var tagged = segment
            tagged.startTime += offset
            tagged.endTime += offset
            if isOnlineMeeting {
                tagged.audioSource = .system
            }
            MeetingStore.shared.appendSegment(tagged, to: meetingID, persistImmediately: false)
        }

        do {
            let locale = TranscriptionLanguage(rawValue: meeting.transcriptionLanguage ?? "auto")?.locale
            recordingLocale = locale
            try await engine.setup(locale: locale)
        } catch {
            errorMessage = RecordingError.speechEngineSetupFailed(error.localizedDescription).localizedDescription
            logger.error("Speech engine setup failed: \(error.localizedDescription, privacy: .public)")
            recordingState = .idle
            return
        }

        speechEngine = engine

        // Create diarizer (not yet initialized — audio will buffer once init completes)
        let diarizer = DiarizationManager(
            config: DiarizerConfig(clusteringThreshold: 0.65, minSpeechDuration: 2.0)
        )
        diarizationManager = diarizer

        // Start audio capture IMMEDIATELY — don't wait for diarization models
        switch meeting.recordingMode {
        case .inPerson, .voiceNote:
            await startMicrophoneRecording(engine: engine, diarizer: diarizer)

        case .onlineMeeting:
            await startSystemAudioRecording(engine: engine, diarizer: diarizer)
        }

        // If audio capture failed to start, clean up and bail
        if recordingState != .recording {
            diarizationManager = nil
            recordingState = .idle
            return
        }

        // Initialize diarization in background (models download while transcription runs)
        let recordingMode = meeting.recordingMode
        let meetingSpeakers = meeting.speakers
        diarizationInitTask = Task { @MainActor [weak self] in
            self?.speakerDetectionStatus = .downloadingModels
            do {
                // No timeout — model download from HuggingFace can take several minutes on
                // first run. Recording is unaffected; this task runs entirely in background.
                try await diarizer.initialize()
                if !meetingSpeakers.isEmpty {
                    await diarizer.initializeKnownSpeakers(meetingSpeakers)
                }
            } catch {
                self?.speakerDetectionStatus = .unavailable
                self?.logger.warning("Diarization init failed (continuing without): \(error.localizedDescription, privacy: .public)")
                return
            }

            guard diarizer.isEnabled, recordingMode != .voiceNote else {
                self?.speakerDetectionStatus = .inactive
                return
            }

            self?.isPeriodicDiarizationStopped = false
            self?.hasPeriodicDiarizationResults = false
            self?.speakerDetectionStatus = .active

            // Audio accumulates during recording via processAudioBuffer().
            // Full diarization runs after recording stops via processCompleteRecording()
            // for maximum accuracy — the model sees the entire conversation context.
            self?.logger.info("Diarization models ready — audio accumulating for post-recording processing")
        }

        if isRecording {
            logger.info("Recording started for meeting \(meetingID)")
        }
    }

    private func startMicrophoneRecording(engine: SpeechTranscriberEngine, diarizer: DiarizationManager) async {
        // Mic permission already verified in startRecording() before engine setup
        startAudioBufferConsumer(engine: engine, diarizer: diarizer)
        let continuation = audioBufferContinuation
        audioRecorder.onAudioBuffer = { buffer in
            continuation?.yield(buffer)
        }

        do {
            try audioRecorder.startRecording()
            recordingState = .recording
            isMicActive = true
        } catch {
            errorMessage = RecordingError.micStartFailed(error.localizedDescription).localizedDescription
            logger.error("Mic start failed: \(error.localizedDescription, privacy: .public)")
            speechEngine = nil
            diarizationManager = nil
        }
    }

    private func startSystemAudioRecording(engine: SpeechTranscriberEngine, diarizer: DiarizationManager) async {
        guard let meetingID = currentMeetingID else { return }
        let offset = timeOffset

        // Start system audio capture
        do {
            try await systemCapture.startCapture()
        } catch {
            if let audioError = error as? SystemAudioError, case .tapCreationFailed = audioError {
                errorMessage = RecordingError.systemAudioPermissionDenied.localizedDescription
            } else {
                errorMessage = RecordingError.systemAudioStartFailed(error.localizedDescription).localizedDescription
            }
            logger.error("System capture failed: \(error.localizedDescription, privacy: .public)")
            speechEngine = nil
            diarizationManager = nil
            return
        }

        // Record system audio to disk so the Recording panel can play it back.
        if let captureFormat = systemCapture.captureFormat {
            let fileURL = FileManager.default.temporaryDirectory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("caf")
            systemAudioTempURL = fileURL
            do {
                systemAudioFile = try AVAudioFile(forWriting: fileURL, settings: captureFormat.settings)
                try? (fileURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            } catch {
                logger.error("Failed to create system audio recording file: \(error.localizedDescription, privacy: .public)")
            }
        }

        // System audio callback: write to file AND feed to transcription stream.
        if audioBufferContinuation == nil {
            startAudioBufferConsumer(engine: engine, diarizer: diarizer)
        }
        let continuation = audioBufferContinuation
        let sysFileRef = systemAudioFile
        systemCapture.onAudioBuffer = { buffer in
            if let ref = sysFileRef {
                do {
                    try ref.write(from: buffer)
                } catch {
                    os_log(.error, "System audio file write failed: %{public}@", error.localizedDescription)
                }
            }
            continuation?.yield(buffer)
        }

        // Mic is NOT auto-started for system audio recordings.
        // User can manually enable it via the mic toggle (enableMic()).
        // This avoids duplicate transcription from system audio bleed-through into the mic.

        recordingState = .recording
        isCapturingSystemAudio = true
    }

    // MARK: - Stop Recording

    func stopRecording() async {
        guard recordingState == .recording || recordingState == .starting,
              let meetingID = currentMeetingID
        else { return }
        recordingState = .stopping

        // Ensure UI flags are always reset, even if engine finalization hangs
        defer {
            recordingState = .idle
            isCapturingSystemAudio = false
            isMicActive = false
        }

        let meeting = MeetingStore.shared.meetings.first { $0.id == meetingID }
        let mode = meeting?.recordingMode ?? .inPerson
        let finalElapsedTime = elapsedTime

        await teardownAudioPipeline()

        // Persist recording audio:
        // • Both sources (online meeting + mic on): mix into one file
        // • System audio only (online meeting, mic off): save system audio
        // • Mic only (in-person/voice note): save mic audio
        let systemTempURL = systemAudioTempURL
        systemAudioTempURL = nil

        do {
            if let sysURL = systemTempURL, let mURL = audioRecorder.tempFileURL {
                if let mixedURL = await mixAudioFiles(systemURL: sysURL, micURL: mURL, meetingID: meetingID) {
                    MeetingStore.shared.setAudioFileURL(mixedURL, for: meetingID)
                    try? FileManager.default.removeItem(at: sysURL)
                } else {
                    // Mix failed — fall back to system audio only
                    let url = try moveRecordingFile(from: sysURL, meetingID: meetingID)
                    MeetingStore.shared.setAudioFileURL(url, for: meetingID)
                }
            } else if let sysURL = systemTempURL {
                let url = try moveRecordingFile(from: sysURL, meetingID: meetingID)
                MeetingStore.shared.setAudioFileURL(url, for: meetingID)
            } else if let mURL = audioRecorder.tempFileURL {
                let url = try moveRecordingFile(from: mURL, meetingID: meetingID)
                MeetingStore.shared.setAudioFileURL(url, for: meetingID)
            }
        } catch {
            logger.error("Failed to persist recording file: \(error.localizedDescription, privacy: .public)")
        }
        audioRecorder.clearTemporaryFile()

        MeetingStore.shared.updateDuration(finalElapsedTime, for: meetingID)

        // Clear session state
        currentMeetingID = nil
        timeOffset = 0

        // Drop reference but do NOT cancel — if models are mid-download, let them finish
        // and cache so the next recording session finds them immediately.
        diarizationInitTask = nil
        isPeriodicDiarizationStopped = true

        // Launch diarization + post-recording AI as a non-blocking background pipeline
        let capturedDiarizer = diarizationManager
        diarizationManager = nil
        isDiarizing = capturedDiarizer != nil

        postRecordingTask = Task { [weak self] in
            if let diarizer = capturedDiarizer {
                await self?.processDiarization(for: meetingID, diarizer: diarizer)
            }
            guard let self else { return }
            if mode == .onlineMeeting {
                addYouSpeaker(for: meetingID)
            }
            postRecordingPipeline.start(for: meetingID)
            MeetingStore.shared.saveMeeting(id: meetingID)
        }

        logger.info("Recording stopped for meeting \(meetingID)")
    }

    /// Mixes system audio and mic audio into a single M4A file saved to the Recordings directory.
    /// Both tracks start at position zero; the longer one defines the total duration.
    /// Returns nil if mixing fails; caller should fall back to system-audio-only.
    private func mixAudioFiles(systemURL: URL, micURL: URL, meetingID: UUID) async -> URL? {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let recordingsDir = support.appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        try? fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let outputURL = recordingsDir.appending(path: "\(meetingID.uuidString).m4a")
        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(at: outputURL)
        }

        let systemAsset = AVURLAsset(url: systemURL)
        let micAsset = AVURLAsset(url: micURL)
        let composition = AVMutableComposition()

        guard let sysTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
            let micTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            logger.error("Failed to create composition tracks for audio mix")
            return nil
        }

        do {
            let sysSrcTracks = try await systemAsset.loadTracks(withMediaType: .audio)
            let micSrcTracks = try await micAsset.loadTracks(withMediaType: .audio)

            if let src = sysSrcTracks.first {
                let dur = try await systemAsset.load(.duration)
                try sysTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
            }
            if let src = micSrcTracks.first {
                let dur = try await micAsset.load(.duration)
                try micTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
            }
        } catch {
            logger.error("Failed to build audio composition: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        )
        else {
            logger.error("Failed to create AVAssetExportSession for audio mix")
            return nil
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        await exporter.export()

        guard exporter.status == .completed else {
            logger.error("Audio mix export failed: \(exporter.error?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        }

        logger.info("Mixed system + mic audio → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    /// Moves a temporary audio file to a stable per-meeting location in Application Support.
    /// Preserves the source file extension (.wav for mic, .caf for system audio).
    private func moveRecordingFile(from tempURL: URL, meetingID: UUID) throws -> URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let recordingsDir = support.appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
        try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        let ext = tempURL.pathExtension.isEmpty ? "wav" : tempURL.pathExtension
        let dest = recordingsDir.appending(path: "\(meetingID.uuidString).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// Tears down audio callbacks, buffer streams, capture devices, and transcription engines.
    private func teardownAudioPipeline() async {
        // Null out callbacks BEFORE stopping engines to prevent in-flight buffers
        // from racing with engine teardown (weak refs could become nil mid-callback)
        audioRecorder.onAudioBuffer = nil
        systemCapture.onAudioBuffer = nil

        // Terminate audio buffer streams so consumer tasks finish
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioBufferConsumerTask?.cancel()
        audioBufferConsumerTask = nil
        micBufferContinuation?.finish()
        micBufferContinuation = nil
        micBufferConsumerTask?.cancel()
        micBufferConsumerTask = nil

        // Stop all audio sources immediately
        if systemCapture.isCapturing {
            systemCapture.stopCapture()
        }
        systemCapture.teardown()
        // Close and flush the system audio file now that no more IO callbacks will fire.
        systemAudioFile = nil
        audioRecorder.stopRecording()

        // Finalize transcription engines (may take up to 10s timeout)
        if let engine = speechEngine {
            await engine.finish()
        }
        speechEngine = nil

        if let micEngine = micSpeechEngine {
            await micEngine.finish()
        }
        micSpeechEngine = nil
    }

    // MARK: - Mid-Recording System Audio Toggle

    /// Enable system audio capture mid-recording (e.g., user joins an online meeting).
    func enableSystemAudio() async {
        guard isRecording, let meetingID = currentMeetingID, !isCapturingSystemAudio else { return }

        do {
            try await systemCapture.startCapture()
        } catch {
            if let audioError = error as? SystemAudioError, case .tapCreationFailed = audioError {
                errorMessage = RecordingError.systemAudioPermissionDenied.localizedDescription
            } else {
                errorMessage = RecordingError.systemAudioStartFailed(error.localizedDescription).localizedDescription
            }
            logger.error("Mid-recording system capture failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Open a file to persist system audio for playback (same as startSystemAudioRecording).
        // Without this, systemAudioTempURL stays nil and stopRecording() saves only mic audio.
        if systemAudioFile == nil, let captureFormat = systemCapture.captureFormat {
            let fileURL = FileManager.default.temporaryDirectory
                .appending(component: UUID().uuidString)
                .appendingPathExtension("caf")
            systemAudioTempURL = fileURL
            do {
                systemAudioFile = try AVAudioFile(forWriting: fileURL, settings: captureFormat.settings)
                try? (fileURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            } catch {
                logger.error("Failed to create system audio file in enableSystemAudio: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Feed system audio to the transcription stream AND write to disk for playback.
        let continuation = audioBufferContinuation
        let sysFileRef = systemAudioFile
        systemCapture.onAudioBuffer = { buffer in
            if let ref = sysFileRef {
                do {
                    try ref.write(from: buffer)
                } catch {
                    os_log(.error, "System audio file write failed (mid-recording): %{public}@", error.localizedDescription)
                }
            }
            continuation?.yield(buffer)
        }

        // Update meeting mode to reflect system audio capture
        if let idx = MeetingStore.shared.meetings.firstIndex(where: { $0.id == meetingID }) {
            MeetingStore.shared.meetings[idx].recordingMode = .onlineMeeting
        }

        isCapturingSystemAudio = true
        logger.info("System audio enabled mid-recording for meeting \(meetingID)")
    }

    /// Disable system audio capture mid-recording.
    func disableSystemAudio() {
        guard isRecording, isCapturingSystemAudio else { return }
        systemCapture.stopCapture()
        systemCapture.onAudioBuffer = nil
        isCapturingSystemAudio = false
        logger.info("System audio disabled mid-recording")
    }

    /// Enable microphone mid-recording (e.g., user started with system audio only).
    func enableMic() async {
        guard isRecording, !isMicActive, !isStopping else { return }

        let hasPermission = await checkMicrophonePermission()
        // Re-check recording state after async permission check — recording may have stopped.
        guard hasPermission else {
            errorMessage = RecordingError.micPermissionDenied.localizedDescription
            return
        }
        guard isRecording, !isMicActive else { return }

        if isCapturingSystemAudio {
            // Single-engine approach (Otter-style): feed mic audio to the SAME primary
            // speech engine + diarizer. No separate mic engine — avoids duplicate transcription
            // from system audio bleed-through. Sortformer handles speaker separation.
            let continuation = audioBufferContinuation
            audioRecorder.onAudioBuffer = { buffer in
                continuation?.yield(buffer)
            }
        } else {
            // In-person mode: mic is the only source, needs its own engine
            guard let meetingID = currentMeetingID else { return }
            let offset = timeOffset
            let micEngine = SpeechTranscriberEngine()
            micEngine.onFinalSegment = { @MainActor segment in
                var tagged = segment
                tagged.startTime += offset
                tagged.endTime += offset
                tagged.audioSource = .microphone
                tagged.speakerLabel = "You"
                MeetingStore.shared.appendSegment(tagged, to: meetingID, persistImmediately: false)
            }

            do {
                try await micEngine.setup(locale: recordingLocale)
                micSpeechEngine = micEngine
                // Dedicated mic stream for the separate mic engine
                let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
                micBufferContinuation = micCont
                micBufferConsumerTask = Task { [weak micEngine] in
                    for await buffer in micStream {
                        guard !Task.isCancelled else { break }
                        micEngine?.streamAudio(buffer)
                    }
                }
                audioRecorder.onAudioBuffer = { buffer in
                    micCont.yield(buffer)
                }
            } catch {
                errorMessage = RecordingError.micStartFailed(error.localizedDescription).localizedDescription
                logger.error("Mid-recording mic start failed: \(error.localizedDescription, privacy: .public)")
                micSpeechEngine = nil
                return
            }
        }

        do {
            try audioRecorder.startRecording()
            isMicActive = true
            // swiftformat:disable:next redundantSelf
            logger.info("Mic enabled mid-recording (single-engine: \(self.isCapturingSystemAudio))")
        } catch {
            errorMessage = RecordingError.micStartFailed(error.localizedDescription).localizedDescription
            logger.error("Mid-recording mic start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Disable microphone mid-recording.
    func disableMic() {
        guard isRecording, isMicActive else { return }
        // stopTap() stops the engine and tap but keeps the audio file open so a subsequent
        // enableMic() → startRecording() can continue appending to the same file.
        audioRecorder.stopTap()
        audioRecorder.onAudioBuffer = nil

        // Clean up dedicated mic buffer stream
        micBufferContinuation?.finish()
        micBufferContinuation = nil
        micBufferConsumerTask?.cancel()
        micBufferConsumerTask = nil

        // Only clean up mic engine if we created a separate one (in-person mode).
        // In system audio mode, mic feeds the primary engine — no separate engine to clean up.
        if !isCapturingSystemAudio, let micEngine = micSpeechEngine {
            Task { await micEngine.finish() }
            micSpeechEngine = nil
        }

        isMicActive = false
        logger.info("Mic disabled mid-recording")
    }

    // MARK: - Audio Buffer Stream

    /// Creates a single-consumer async stream for audio buffers.
    /// One MainActor Task processes all buffers sequentially, instead of spawning a new Task per buffer.
    private func startAudioBufferConsumer(engine: SpeechTranscriberEngine, diarizer: DiarizationManager) {
        // Clean up any existing stream
        audioBufferContinuation?.finish()
        audioBufferConsumerTask?.cancel()

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        audioBufferContinuation = continuation

        audioBufferConsumerTask = Task { [weak engine, weak diarizer] in
            for await buffer in stream {
                guard !Task.isCancelled else { break }
                engine?.streamAudio(buffer)
                diarizer?.processAudioBuffer(buffer)
            }
        }
    }

    // MARK: - Permissions

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
}
