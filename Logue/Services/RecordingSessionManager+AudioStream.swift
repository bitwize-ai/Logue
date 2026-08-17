import AVFoundation
import Foundation

/// Every captured buffer's path from a capture source to the transcriber, the diarizer and the
/// file — one consumer, in arrival order, so the three never see a different sequence.
extension RecordingSessionManager {
    /// Creates a single-consumer async stream for audio buffers.
    /// One MainActor Task processes all buffers sequentially, instead of spawning a new Task per buffer.
    func startAudioBufferConsumer(engine: SpeechTranscriberEngine, diarizer: DiarizationManager) {
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
    func admitToTranscriber(
        _ buffer: AVAudioPCMBuffer,
        diarizer: DiarizationManager?
    ) async -> [AVAudioPCMBuffer] {
        guard let vad = await diarizer?.ensureVadManager() else { return [buffer] }
        return await speechGate.admit(buffer, at: sessionElapsed, vad: vad)
    }
}
