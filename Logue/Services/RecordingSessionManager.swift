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
/// Cohesive recording state machine: start, stop, microphone mute, and arming the system-audio tap.
/// Which sources a session uses is not asked of the user — the microphone always runs, and the tap
/// arms itself the first time anything plays through the speakers.
/// Device-loss handling lives in `+DeviceLoss`; the rest is kept as one unit, because splitting it
/// further would require widening most of the private state to internal.
@Observable
@MainActor
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
        /// Rebuilding an interrupted session at launch.
        ///
        /// Held for the whole of recovery because it shares this object with a live session: the
        /// audio composition it runs ends by clearing `audioRecorder`'s temporary file, and its
        /// working directory is the one a re-recording of the same meeting would use. A recording
        /// starting underneath it would lose its own audio.
        case recovering
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

    /// Whether an interrupted session is being rebuilt.
    ///
    /// Surfaced because the rebuild holds `recordingState` for minutes on a long meeting —
    /// splicing a multi-hour file, then initialising the diarizer — and `startRecording`
    /// refuses throughout. Without this the toolbar rendered a live, enabled Record button the
    /// whole time, so a press looked accepted and did nothing.
    var isRecovering: Bool {
        recordingState == .recovering
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

    // Extension-visible: +DeviceLoss
    /// Whether the user has muted the microphone.
    ///
    /// Distinct from `isMicActive`, which only says whether the tap is running. A device dropping
    /// also stops the tap, so without recording the *intent* separately a headset renegotiating
    /// while muted would be treated as capture to restore, and a muted microphone would quietly
    /// start recording again.
    private(set) var isMicMuted = false

    /// A short, non-blocking note about capture — a device that went away, a fallback that was
    /// taken. Nil when there is nothing to say. Never a dialog: a meeting keeps running while the
    /// user is not looking at the screen.
    var captureNotice: String?
    private var postRecordingTask: Task<Void, Never>?
    // Extension-visible: +Checkpoint
    var checkpointTask: Task<Void, Never>?
    private var diarizationInitTask: Task<Void, Never>?

    /// Handles AI title/summary/space-suggestion after recording stops.
    let postRecordingPipeline = PostRecordingPipeline()

    /// Current volatile transcription text (in-progress, not yet finalized).
    ///
    /// One engine, so one source of text. There used to be a second engine for the case where a
    /// session started on system audio and the microphone was switched on later; the microphone now
    /// always starts first, so that case cannot arise and the engine it needed is gone.
    var volatileText: String {
        speechEngine?.volatileText ?? ""
    }

    // MARK: - Engines

    let audioRecorder = AudioRecorder()
    let systemCapture = SystemAudioCapture()
    private var speechEngine: SpeechTranscriberEngine?
    // Extension-visible: +DeviceLoss, +Diarization
    var diarizationManager: DiarizationManager?

    /// Watches for anything playing through the speakers, so the system-audio tap can arm itself
    /// rather than waiting to be switched on.
    private let systemAudioArming = SystemAudioArmingMonitor()

    // Extension-visible: +DeviceLoss
    /// Keeps silence out of the transcriber. Only ever consulted for microphone audio, and never
    /// for what is written to disk or handed to the diarizer.
    let speechGate = MicrophoneSpeechGate()

    /// Notices when the microphone we are recording from goes away.
    private let deviceMonitor = CaptureDeviceMonitor()

    /// This session's durable working directory, holding the audio and the checkpoint until the
    /// recording stops cleanly.
    private var inProgressDirectory: URL?

    /// Whether this launch has already put the Screen Recording prompt on screen. Deliberately not
    /// persisted — see `ensureScreenRecordingAccess()`.
    private var hasRequestedScreenRecordingAccess = false

    private var recordingLocale: Locale?

    // Extension-visible: +Checkpoint
    /// Time offset applied when continuing recording on a meeting that already has segments.
    /// New segment timestamps and elapsed time are shifted forward by this amount.
    var timeOffset: TimeInterval = 0

    // Extension-visible: +Checkpoint
    /// When the current recording session began. Capture sources are placed on the diarization
    /// timeline against this rather than against their own clocks, because a device's clock
    /// restarts from zero every time it is toggled and would put resumed audio back at the start
    /// of the meeting.
    var sessionStartDate: Date?

    // Extension-visible: +DeviceLoss
    /// Seconds since this recording session started, independent of any one capture device.
    var sessionElapsed: TimeInterval {
        sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    // Extension-visible: +DeviceLoss
    /// Where each stretch of the mic recording belongs on the meeting's timeline. The mic writes one
    /// file across every mute and unmute, with the muted stretches absent from it, so the playback
    /// mix has to lay each activation down separately or everything after the first mute plays early.
    var micSegments = CaptureSegmentTimeline()

    // Extension-visible: +Checkpoint
    /// The same, for the system-audio tap. It can join a meeting already in progress, in which case
    /// its file starts then and laying it down at zero would play the remote side early.
    var systemSegments = CaptureSegmentTimeline()

    /// Seconds written to the system-audio file, accumulated on the capture thread as each buffer
    /// lands. Counted rather than read back from the file, which that thread is concurrently writing.
    private let systemWrittenSeconds = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    // Extension-visible: +Checkpoint
    /// Seconds of audio the system-audio file holds right now.
    var systemRecordedDuration: TimeInterval {
        systemWrittenSeconds.withLock { $0 }
    }

    /// Open AVAudioFile for writing system audio in online meeting mode.
    /// Kept open during recording; set to nil in teardownAudioPipeline() to flush and close it.
    private var systemAudioFile: AVAudioFile?
    // Extension-visible: +Checkpoint
    /// Temp path for the system audio recording file. Preserved after teardown so stopRecording() can move it.
    var systemAudioTempURL: URL?

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

    // Extension-visible: +DeviceLoss
    /// Single-consumer stream that coalesces audio buffers from the audio thread.
    /// Replaces per-buffer `Task { @MainActor }` creation to prevent MainActor flooding.
    var audioBufferContinuation: AsyncStream<CapturedAudio>.Continuation?
    private var audioBufferConsumerTask: Task<Void, Never>?

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

    /// The louder of the two sources. A source that is not running reports zero, so this needs to
    /// know nothing about what kind of session this is.
    var audioLevel: Float {
        guard currentMeetingID != nil else { return 0 }
        return max(systemCapture.audioLevel, audioRecorder.audioLevel)
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
        guard recordingState == .idle else {
            if recordingState == .recovering {
                // Said out loud, because the refusal is otherwise invisible and two of the three
                // ways a recording starts destroy the request rather than retrying it: the
                // workspace clears `pendingAutoRecord` before awaiting this, so automatic
                // capture silently does nothing, and the menu-bar item shows the recording panel
                // for a session that never began.
                logger.info("Not starting a recording while an interrupted session is being rebuilt")
                captureNotice = "Finishing an interrupted recording…"
            }
            return
        }
        recordingState = .starting
        errorMessage = nil

        // Check microphone permission FIRST — before any heavy setup or waiting
        // This ensures the OS permission dialog appears immediately on first use.
        // Every session captures the microphone, so this is never conditional.
        let hasPermission = await checkMicrophonePermission()
        guard hasPermission else {
            errorMessage = RecordingError.micPermissionDenied.localizedDescription
            recordingState = .idle
            return
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
        speechGate.reset()

        // Somewhere the audio survives the app not reaching stopRecording(). The directory existing
        // afterwards is what tells the next launch this session was interrupted.
        do {
            inProgressDirectory = try InProgressRecordingStore.directory(for: meetingID)
            audioRecorder.inProgressDirectory = inProgressDirectory
        } catch {
            inProgressDirectory = nil
            audioRecorder.inProgressDirectory = nil
            logger.error("No durable location for this recording: \(error.localizedDescription, privacy: .public)")
        }

        // Start audio capture IMMEDIATELY — don't wait for diarization models.
        //
        // The microphone always runs. What kind of session this is — a call, a room, a voice note —
        // is something we find out from what actually gets captured, not something the user is asked
        // to declare before they have started.
        await startMicrophoneRecording(engine: engine, diarizer: diarizer)

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
            // From here on the session decides for itself whether it is also a call.
            systemAudioArming.start { [weak self] in
                Task { @MainActor in await self?.armSystemAudio() }
            }
            deviceMonitor.start { [weak self] decision, deviceName in
                self?.handleMicrophoneLoss(decision, deviceName: deviceName)
            }
            startCheckpointing()
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
            // A mute belongs to the session it was made in. Left set, it survived into every
            // later meeting of the same run: the mic looked live, and the first device
            // renegotiation refused to resume it — silent capture loss, which is the failure
            // the device-loss handling exists to prevent.
            isMicMuted = false
            micSegments.sourceStarted(atSessionTime: 0, fileDuration: 0)
        } catch {
            errorMessage = RecordingError.micStartFailed(error.localizedDescription).localizedDescription
            logger.error("Mic start failed: \(error.localizedDescription, privacy: .public)")
            speechEngine = nil
            diarizationManager = nil
        }
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
            isMicMuted = false
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

        // The session reached its end, so there is nothing to recover. Clearing this is what stops
        // the next launch treating it as an interrupted recording.
        InProgressRecordingStore.clear(meetingID: meetingID)
        inProgressDirectory = nil
        audioRecorder.inProgressDirectory = nil

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
        // Nothing left to arm, to watch, or to write down once the session is over.
        systemAudioArming.stop()
        deviceMonitor.stop()
        checkpointTask?.cancel()
        checkpointTask = nil
        captureNotice = nil

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
    }

    // MARK: - Arming System Audio

    /// Starts the system-audio tap for the rest of the session.
    ///
    /// Called by the arming monitor the first time anything plays through the speakers, never by the
    /// user. Once armed the tap stays up: a meeting has quiet stretches, and stopping and restarting
    /// across them would open a `CaptureSegmentTimeline` placement for each one and gain nothing.
    private func armSystemAudio() async {
        guard isRecording, !isStopping, let meetingID = currentMeetingID, !isCapturingSystemAudio else { return }

        guard await ensureScreenRecordingAccess() else { return }
        // Access may have been asked for interactively; the session can have ended meanwhile.
        guard isRecording, !isStopping, !isCapturingSystemAudio else { return }

        do {
            try await systemCapture.startCapture()
        } catch {
            if let audioError = error as? SystemAudioError, case .tapCreationFailed = audioError {
                errorMessage = RecordingError.systemAudioPermissionDenied.localizedDescription
            } else {
                errorMessage = RecordingError.systemAudioStartFailed(error.localizedDescription).localizedDescription
            }
            logger.error("Arming system capture failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // ScreenCaptureKit takes a moment to come up, and the session can stop inside it.
        guard isRecording, !isStopping else {
            systemCapture.stopCapture()
            return
        }

        // Open a file to persist system audio for playback. Without this, systemAudioTempURL stays
        // nil and stopRecording() saves only mic audio.
        if systemAudioFile == nil, let captureFormat = systemCapture.captureFormat {
            let fileURL = (inProgressDirectory ?? FileManager.default.temporaryDirectory)
                .appending(component: UUID().uuidString)
                .appendingPathExtension("caf")
            systemAudioTempURL = fileURL
            do {
                systemAudioFile = try AVAudioFile(forWriting: fileURL, settings: captureFormat.settings)
            } catch {
                logger.error("Failed to create system audio file while arming: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Feed system audio to the transcription stream AND write to disk for playback.
        // It joins the diarization timeline where the meeting is now, not at its start.
        let systemJoinedAt = sessionElapsed
        diarizationManager?.beginSource(.system, atSessionTime: systemJoinedAt)
        systemSegments.sourceStarted(atSessionTime: systemJoinedAt, fileDuration: systemRecordedDuration)
        installSystemAudioTap()

        // The mode is a description of what this session turned out to be, and this is the only
        // place it is decided. A voice note is a statement of intent made at creation and is not
        // overwritten by having played something aloud.
        if let idx = MeetingStore.shared.meetings.firstIndex(where: { $0.id == meetingID }),
           MeetingStore.shared.meetings[idx].recordingMode != .voiceNote
        {
            MeetingStore.shared.meetings[idx].recordingMode = .onlineMeeting
        }

        isCapturingSystemAudio = true
        logger.info("System audio armed for meeting \(meetingID)")
    }

    /// Whether the ScreenCaptureKit tap may run.
    ///
    /// Preflighted on every arming, because the grant is not permanent: macOS ties it to the app's
    /// code signature, so an update, a rebuild, or moving the app revokes it. The *request* is made
    /// at most once per launch — arming happens on its own now, so an ungranted permission must not
    /// become a dialog at the start of every meeting. Remembering the refusal across launches was
    /// worse still: a grant that lapsed could never be recovered from, and the app went on quietly
    /// not recording the far side of every call.
    private func ensureScreenRecordingAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        guard !hasRequestedScreenRecordingAccess else {
            noteSystemAudioUnavailable()
            return false
        }
        hasRequestedScreenRecordingAccess = true

        guard CGRequestScreenCaptureAccess() else {
            noteSystemAudioUnavailable()
            return false
        }
        return true
    }

    /// Says that this session is recording the microphone only, and what would change that.
    ///
    /// Saying nothing is the worst outcome available here: the user believes the remote side is
    /// being recorded, and discovers it was not when they go looking for it afterwards.
    private func noteSystemAudioUnavailable() {
        captureNotice = "System audio needs Screen Recording access — enable Logue in "
            + "System Settings › Privacy & Security › Screen Recording"
        logger.info("System audio not armed — screen recording access not granted")
    }

    // MARK: - Microphone Mute

    /// Mutes or unmutes the microphone mid-session.
    ///
    /// A mute, not a mode. The session is a microphone session either way, and the one engine that
    /// started with it keeps running — muting only stops the tap feeding it. The diarization
    /// timeline and the segment timeline record the silence as a gap where it belongs, because a
    /// capture device's own clock restarts at zero every time it is toggled and would otherwise put
    /// everything after the mute back at the start of the meeting.
    func setMicMuted(_ muted: Bool) {
        guard isRecording, !isStopping, muted == isMicActive else { return }
        isMicMuted = muted

        guard muted else {
            resumeMicrophoneCapture()
            return
        }

        // Close the activation at the file's current length before the tap stops, so the playback
        // mix knows how much of the file belongs to the stretch just recorded.
        micSegments.sourceStopped(fileDuration: audioRecorder.recordedDuration)
        // stopTap() stops the engine and tap but keeps the audio file open, so unmuting continues
        // appending to the same file.
        audioRecorder.stopTap()
        audioRecorder.onAudioBuffer = nil
        isMicActive = false
        logger.info("Microphone muted")
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

        audioBufferConsumerTask = Task { [weak self, weak engine, weak diarizer] in
            for await captured in stream {
                guard !Task.isCancelled else { break }

                // The diarizer and the file get every buffer, always. Only the transcriber is
                // gated, and only on the microphone: the system tap is already silent when nothing
                // is playing, and gating it could cost a remote speaker's opening word for nothing.
                diarizer?.processAudioBuffer(captured.buffer, from: captured.source)

                guard captured.source == .microphone, let self else {
                    engine?.streamAudio(captured.buffer)
                    continue
                }

                for buffer in await admitToTranscriber(captured.buffer, diarizer: diarizer) {
                    engine?.streamAudio(buffer)
                }
            }
        }
    }

    /// Runs a microphone buffer past the voice-activity gate, falling back to passing it straight
    /// through whenever the model is not available.
    private func admitToTranscriber(
        _ buffer: AVAudioPCMBuffer,
        diarizer: DiarizationManager?
    ) async -> [AVAudioPCMBuffer] {
        guard let vad = await diarizer?.ensureVadManager() else { return [buffer] }
        return await speechGate.admit(buffer, at: sessionElapsed, vad: vad)
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
