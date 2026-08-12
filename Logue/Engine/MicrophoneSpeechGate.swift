import AVFoundation
import FluidAudio
import Foundation
import os.log

/// Decides, buffer by buffer, what the transcriber hears from the microphone.
///
/// Owns everything that decision needs: the conversion to the 16 kHz mono the voice-activity model
/// takes, the fixed-size chunking it requires, the model's streaming state, the gate itself and the
/// pre-roll that gives an utterance back its first consonant.
///
/// What it deliberately does not own is the audio. Callers hand it a buffer and receive back the
/// buffers the transcriber should be given — the file on disk and the diarization timeline are fed
/// separately and unconditionally, so nothing here can put a hole in the recording.
@MainActor
final class MicrophoneSpeechGate {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SpeechGate")

    private var gate = TranscriptionGate(tail: AppConstants.Transcription.gateTail)
    private var preRoll = PreRollBuffer(maxDuration: AppConstants.Transcription.gatePreRoll)
    private var streamState: VadStreamState?
    private var pending: [Float] = []
    private let converter = BufferConverter()

    /// The format the voice-activity model takes. Built once; a nil here disables gating rather than
    /// failing, which is the right way round — the transcriber keeps working.
    private static let vadFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(VadManager.sampleRate),
        channels: 1,
        interleaved: false
    )

    /// Whether gating is currently suppressing audio. Drives nothing but diagnostics.
    private(set) var isOpen = false

    func reset() {
        gate.reset()
        preRoll.removeAll()
        streamState = nil
        pending.removeAll(keepingCapacity: true)
        isOpen = false
    }

    /// Runs one microphone buffer past the gate.
    ///
    /// Returns what the transcriber should be given: nothing while the gate is shut, the held
    /// pre-roll and this buffer at the moment it opens, and this buffer alone while it stays open.
    /// Anything that goes wrong returns the buffer, so a failure degrades to today's behaviour
    /// rather than to silence.
    func admit(
        _ buffer: AVAudioPCMBuffer,
        at sessionTime: TimeInterval,
        vad: VadManager
    ) async -> [AVAudioPCMBuffer] {
        guard let samples = monoSamples(from: buffer) else { return [buffer] }

        pending.append(contentsOf: samples)

        var state: VadStreamState = if let existing = streamState {
            existing
        } else {
            await vad.makeStreamState()
        }

        while pending.count >= VadManager.chunkSize {
            let chunk = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            do {
                let result = try await vad.processStreamingChunk(chunk, state: state)
                state = result.state
                switch result.event?.kind {
                case .speechStart: gate.speechStarted()
                case .speechEnd: gate.speechEnded(at: sessionTime)
                case nil: break
                }
            } catch {
                logger.warning("VAD chunk failed, passing audio through: \(error.localizedDescription, privacy: .public)")
                streamState = state
                preRoll.removeAll()
                return [buffer]
            }
        }

        streamState = state
        gate.advance(to: sessionTime)
        isOpen = gate.isOpen

        guard gate.isOpen else {
            preRoll.append(buffer)
            return []
        }
        return preRoll.drain() + [buffer]
    }

    /// Converts a capture buffer to the 16 kHz mono the model takes.
    private func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let format = Self.vadFormat, buffer.frameLength > 0 else { return nil }

        if buffer.format == format, let channelData = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }

        do {
            let converted = try converter.convertBuffer(buffer, to: format)
            guard let channelData = converted.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
        } catch {
            logger.warning("Could not convert for VAD: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
