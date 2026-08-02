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

    /// When the current recording session began. Capture sources are placed on the diarization
    /// timeline against this rather than against their own clocks, because a device's clock
    /// restarts from zero every time it is toggled and would put resumed audio back at the start
    /// of the meeting.
    private var sessionStartDate: Date?

    /// Seconds since this recording session started, independent of any one capture device.
    private var sessionElapsed: TimeInterval {
        sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    /// Where each stretch of the mic recording belongs on the meeting's timeline. The mic writes one
    /// file across every mute and unmute, with the muted stretches absent from it, so the playback
    /// mix has to lay each activation down separately or everything after the first mute plays early.
    private var micSegments = CaptureSegmentTimeline()

    /// The same, for the system-audio tap. It can join a meeting already in progress, in which case
    /// its file starts then and laying it down at zero would play the remote side early.
    private var systemSegments = CaptureSegmentTimeline()

    /// Seconds written to the system-audio file, accumulated on the capture thread as each buffer
    /// lands. Counted rather than read back from the file, which that thread is concurrently writing.
    private let systemWrittenSeconds = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    /// Seconds of audio the system-audio file holds right now.
    private var systemRecordedDuration: TimeInterval {
        systemWrittenSeconds.withLock { $0 }
    }

    /// Open AVAudioFile for writing system audio in online meeting mode.
    /// Kept open during recording; set to nil in teardownAudioPipeline() to flush and close it.
    private var systemAudioFile: AVAudioFile?
    /// Temp path for the system audio recording file. Preserved after teardown so stopRecording() can move it.
    private var systemAudioTempURL: URL?

    /// Installs the system-audio callback: write to disk, count what landed, forward to transcription.
    ///
    /// One copy rather than two. The same closure previously appeared at both the session start and
    /// the mid-recording enable, which is two places for the two to drift apart — and they already
    /// had, differing only in a log string.
    private func installSystemAudioTap() {
        let continuation = audioBufferContinuation
        let sysFileRef = systemAudioFile
        let writtenLock = systemWrittenSeconds
        systemCapture.onAudioBuffer = { buffer in
            if let ref = sysFileRef {
                do {
                    try ref.write(from: buffer)
                    if buffer.format.sampleRate > 0 {
                        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
                        writtenLock.withLock { $0 += seconds }
                    }
                } catch {
                    os_log(.error, "System audio file write failed: %{public}@", error.localizedDescription)
                }
            }
            continuation?.yield(CapturedAudio(buffer: buffer, source: .system))
        }
    }

    // MARK: - Audio Buffer Stream

    /// An audio buffer together with the capture source it came from. The source travels with the
    /// buffer because in an online meeting the mic and the system tap share one stream, and the
    /// diarization timeline has to know which of them it is placing.
    struct CapturedAudio {
        let buffer: AVAudioPCMBuffer
        let source: AudioSource
    }

    /// Single-consumer stream that coalesces audio buffers from the audio thread.
    /// Replaces per-buffer `Task { @MainActor }` creation to prevent MainActor flooding.
    private var audioBufferContinuation: AsyncStream<CapturedAudio>.Continuation?
    private var audioBufferConsumerTask: Task<Void, Never>?
    /// Separate stream for mic-only buffers when a dedicated mic engine is active (in-person enableMic).
    private var micBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var micBufferConsumerTask: Task<Void, Never>?

    // MARK: - Computed

    /// How far into the meeting this recording is.
    ///
    /// Measured from when the session started, not from a capture device's clock. A device's clock
    /// restarts at zero every time it is toggled — `SystemAudioCapture` zeroes its own outright — so
    /// reading one of those meant a three-hour meeting whose system audio was switched off reported
    /// an elapsed time of nothing. That figure is what gets saved as the meeting's duration and what
    /// the post-recording pass measures its audio against, so it has to describe the meeting rather
    /// than whichever device happens to be running.
    var elapsedTime: TimeInterval {
        guard currentMeetingID != nil else { return 0 }
        return sessionElapsed + timeOffset
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

    /// Gives the previous session's post-recording work a moment to finish, then cancels it.
    ///
    /// Racing `await task.value` against a sleep inside a task group cannot do this: the group waits
    /// for every child before returning, and `await task.value` ignores the group's cancellation, so
    /// the timeout was only ever reached after the thing it meant to cut short had finished anyway.
    /// That was harmless while the work was bounded by a thirty-minute buffer; now that a long
    /// recording is processed to its end it could hold a new recording off for tens of minutes. The
    /// task clears the handle when it completes, so waiting on that — with a deadline — leaves us
    /// free to stop waiting.
    private func awaitPreviousPostRecordingTask() async {
        guard postRecordingTask != nil else { return }
        logger.info("Waiting for previous post-recording task to complete before resume...")

        let deadline = ContinuousClock.now + AppConstants.Delays.postRecordingWaitTimeout
        while postRecordingTask != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let task = postRecordingTask {
            task.cancel()
            _ = await task.value // The pass checks for cancellation, so this returns promptly.
            logger.warning("Post-recording task timed out — cancelled and awaited")
        }
        postRecordingTask = nil
    }

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

        await awaitPreviousPostRecordingTask()
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
        sessionStartDate = Date()
        micSegments = CaptureSegmentTimeline()
        systemSegments = CaptureSegmentTimeline()
        systemWrittenSeconds.withLock { $0 = 0 }

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

            self?.speakerDetectionStatus = .active

            // Audio accumulates during recording via processAudioBuffer(). Speakers are identified
            // only once recording stops, by processCompleteWith() over the whole buffer, so the
            // model sees the entire conversation rather than a sliding window of it.
            self?.logger.info("Diarization models ready — audio accumulating for post-recording processing")
        }

        if isRecording {
            logger.info("Recording started for meeting \(meetingID)")
        }
    }

    private func startMicrophoneRecording(engine: SpeechTranscriberEngine, diarizer: DiarizationManager) async {
        // Mic permission already verified in startRecording() before engine setup
        startAudioBufferConsumer(engine: engine, diarizer: diarizer)
        diarizer.beginSource(.microphone, atSessionTime: 0)
        let continuation = audioBufferContinuation
        audioRecorder.onAudioBuffer = { buffer in
            continuation?.yield(CapturedAudio(buffer: buffer, source: .microphone))
        }

        do {
            try audioRecorder.startRecording()
            recordingState = .recording
            isMicActive = true
            micSegments.sourceStarted(atSessionTime: 0, fileDuration: 0)
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
        diarizer.beginSource(.system, atSessionTime: 0)
        // Capture is already running by this point — startCapture() returned above.
        systemSegments.sourceStarted(atSessionTime: 0, fileDuration: 0)
        installSystemAudioTap()

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
        // Close every source's final activation while the counters still hold this session's totals;
        // teardown resets them, and the saved file needs to know how long each one ran.
        var sources = CaptureSources()
        sources.micPlacements = micSegments.finalized(fileDuration: audioRecorder.recordedDuration)
        sources.systemPlacements = systemSegments.finalized(fileDuration: systemRecordedDuration)

        await teardownAudioPipeline()

        sources.systemURL = systemAudioTempURL
        sources.micURL = audioRecorder.tempFileURL
        systemAudioTempURL = nil
        let savedAudio = await persistRecordingAudio(sources: sources, meetingID: meetingID)

        MeetingStore.shared.updateDuration(finalElapsedTime, for: meetingID)

        // Clear session state. Both diarizers time their output from the start of this session's
        // own audio buffer, so post-recording needs the offset the session began at.
        currentMeetingID = nil
        let sessionStart = timeOffset
        timeOffset = 0

        // Drop the reference but do NOT cancel — if models are mid-download, let them finish
        // and cache so the next recording session finds them immediately. Captured so the
        // post-recording pipeline can wait for initialization to land.
        let capturedInitTask = diarizationInitTask
        diarizationInitTask = nil

        // Launch diarization + post-recording AI as a non-blocking background pipeline
        let capturedDiarizer = diarizationManager
        diarizationManager = nil
        isDiarizing = capturedDiarizer != nil

        postRecordingTask = Task { [weak self] in
            // If models are still initializing, Sortformer is not streaming yet and diarization
            // would silently fall back to the less accurate batch path. Wait — but bounded, so a
            // slow first-run download cannot hold up post-recording AI indefinitely.
            if let capturedInitTask {
                await self?.awaitDiarizationInit(capturedInitTask)
            }
            if let diarizer = capturedDiarizer {
                await self?.processDiarization(
                    for: meetingID,
                    diarizer: diarizer,
                    sessionStart: sessionStart,
                    savedAudio: savedAudio,
                    sessionDuration: finalElapsedTime - sessionStart
                )
            }
            guard let self else { return }
            if mode == .onlineMeeting {
                addYouSpeaker(for: meetingID)
            }
            postRecordingPipeline.start(for: meetingID)
            MeetingStore.shared.saveMeeting(id: meetingID)
            // Clears the handle so a subsequent start can see this finished rather than wait it out.
            if currentMeetingID == nil {
                postRecordingTask = nil
            }
        }

        logger.info("Recording stopped for meeting \(meetingID)")
    }

    /// Tears down audio callbacks, buffer streams, capture devices, and transcription engines.
    private func teardownAudioPipeline() async {
        // Null out callbacks BEFORE stopping engines to prevent in-flight buffers
        // from racing with engine teardown (weak refs could become nil mid-callback)
        audioRecorder.onAudioBuffer = nil
        systemCapture.onAudioBuffer = nil
        sessionStartDate = nil

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
        // It joins the diarization timeline where the meeting is now, not at its start.
        let systemJoinedAt = sessionElapsed
        diarizationManager?.beginSource(.system, atSessionTime: systemJoinedAt)
        systemSegments.sourceStarted(atSessionTime: systemJoinedAt, fileDuration: systemRecordedDuration)
        installSystemAudioTap()

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
        systemSegments.sourceStopped(fileDuration: systemRecordedDuration)
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

        let micJoinedAt = sessionElapsed

        if isCapturingSystemAudio {
            // Single-engine approach (Otter-style): feed mic audio to the SAME primary
            // speech engine + diarizer. No separate mic engine — avoids duplicate transcription
            // from system audio bleed-through. Sortformer handles speaker separation.
            // The mic joins the diarization timeline where the meeting is now, not at its start.
            diarizationManager?.beginSource(.microphone, atSessionTime: micJoinedAt)
            let continuation = audioBufferContinuation
            audioRecorder.onAudioBuffer = { buffer in
                continuation?.yield(CapturedAudio(buffer: buffer, source: .microphone))
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
                // Dedicated mic stream for the separate mic engine. It also feeds the diarizer:
                // this is the only source in this mode, so without it speaker detection would go
                // quiet for the rest of the recording the moment the mic was toggled once.
                diarizationManager?.beginSource(.microphone, atSessionTime: micJoinedAt)
                let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
                micBufferContinuation = micCont
                micBufferConsumerTask = Task { [weak micEngine, weak diarizer = diarizationManager] in
                    for await buffer in micStream {
                        guard !Task.isCancelled else { break }
                        micEngine?.streamAudio(buffer)
                        diarizer?.processAudioBuffer(buffer, from: .microphone)
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
            // Opened only now: everything above can fail, and an activation opened against a mic
            // that never started would swallow the next successful one.
            micSegments.sourceStarted(atSessionTime: micJoinedAt, fileDuration: audioRecorder.recordedDuration)
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
        // Close this activation at the file's current length before the tap stops, so the playback
        // mix knows how much of the file belongs to the stretch of meeting just recorded.
        micSegments.sourceStopped(fileDuration: audioRecorder.recordedDuration)
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

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream()
        audioBufferContinuation = continuation

        audioBufferConsumerTask = Task { [weak engine, weak diarizer] in
            for await captured in stream {
                guard !Task.isCancelled else { break }
                engine?.streamAudio(captured.buffer)
                diarizer?.processAudioBuffer(captured.buffer, from: captured.source)
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
