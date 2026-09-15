import AVFoundation
import Foundation

/// Every captured buffer's path from a capture source to the diarizer and the transcriber.
///
/// Two consumers, not three: the file is written on the audio thread *before* the buffer is
/// handed here — system audio at `RecordingSessionManager.captureSystemAudio`, the microphone
/// inside `AudioRecorder` — so nothing in this file touches one, and this ordering says nothing
/// about it. What it does say is that a single `Task` drains the stream, so the diarizer and the
/// transcriber see buffers in arrival order and in the same order as each other.
extension RecordingSessionManager {
    /// Creates a single-consumer async stream for audio buffers.
    /// One MainActor Task processes all buffers sequentially, instead of spawning a new Task per buffer.
    func startAudioBufferConsumer(diarizer: DiarizationManager) {
        // Clean up any existing stream
        audioBufferContinuation?.finish()
        audioBufferConsumerTask?.cancel()

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream()
        audioBufferContinuation = continuation

        audioBufferConsumerTask = Task { [weak self, weak diarizer] in
            for await captured in stream {
                guard !Task.isCancelled else { break }

                // File and diarizer always get the buffer. Live captions get it too — the
                // voice-activity gate was swallowing microphone audio (level meter still moved
                // because it reads the tap directly) so the transcript stayed empty.
                diarizer?.processAudioBuffer(captured.buffer, from: captured.source)
                self?.speechEngine?.streamAudio(captured.buffer)
            }
        }
    }

    /// Runs a microphone buffer past the voice-activity gate, falling back to passing it straight
    /// through whenever the model is not available.
    func admitToTranscriber(
        _ buffer: AVAudioPCMBuffer,
        diarizer: DiarizationManager?
    ) async -> [AVAudioPCMBuffer] {
        guard let vad = await diarizer?.ensureVadManager() else { return [buffer] }
        return await speechGate.admit(buffer, at: sessionElapsed, vad: vad)
    }
}
