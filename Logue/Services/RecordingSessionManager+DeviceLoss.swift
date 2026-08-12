import AVFoundation
import Foundation

/// Keeping a session going when the microphone it is recording from disappears.
///
/// Split out from `RecordingSessionManager` so the core stays inside the type-length limit; the
/// four members it reaches for are marked `// Extension-visible: +DeviceLoss` there.
extension RecordingSessionManager {
    // MARK: - Device Loss

    /// Keeps the session going when the microphone it was recording from disappears.
    ///
    /// Recording never stops and the user is never asked. What changes is where the audio that
    /// follows is placed: a device that comes back or is replaced starts a new activation at the
    /// point the meeting has reached, so the dead stretch stays a gap rather than shifting
    /// everything after it earlier.
    func handleMicrophoneLoss(_ decision: DeviceLossPolicy.Decision, deviceName: String) {
        guard isRecording, !isStopping else { return }

        switch decision {
        case .keepWaiting:
            captureNotice = "\(deviceName) disconnected — waiting for it"
            // The tap is dead but the file stays open, so the activation is closed here and a new
            // one opens if and when capture resumes.
            if isMicActive {
                micSegments.sourceStopped(fileDuration: audioRecorder.recordedDuration)
                audioRecorder.stopTap()
                isMicActive = false
            }

        case .resumeSameDevice:
            captureNotice = nil
            resumeMicrophoneCapture()

        case .fallBackToDefault:
            captureNotice = "Switched to \(deviceName)"
            resumeMicrophoneCapture()
        }
    }

    /// Reopens the microphone on whatever device is current now.
    func resumeMicrophoneCapture() {
        guard !isMicActive else { return }

        let resumedAt = sessionElapsed
        diarizationManager?.beginSource(.microphone, atSessionTime: resumedAt)
        let continuation = audioBufferContinuation
        audioRecorder.onAudioBuffer = { buffer in
            continuation?.yield(CapturedAudio(buffer: buffer, source: .microphone))
        }

        do {
            try audioRecorder.startRecording()
            isMicActive = true
            micSegments.sourceStarted(atSessionTime: resumedAt, fileDuration: audioRecorder.recordedDuration)
            logger.info("Microphone capture resumed")
        } catch {
            audioRecorder.onAudioBuffer = nil
            captureNotice = "Could not reopen the microphone"
            logger.error("Could not resume the microphone: \(error.localizedDescription, privacy: .public)")
        }
    }
}
