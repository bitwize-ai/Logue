import AVFoundation
import Foundation
import os.log

/// Converts capture buffers to the 16 kHz mono the session timeline is built from.
///
/// Lifted out of `DiarizationManager` so it can be tested without a microphone. It is worth testing:
/// the saved recording is written straight from the capture tap, so a conversion that quietly yields
/// silence leaves an audible file and an empty transcript, and nothing in between reports a fault.
final class TimelineAudioConverter {
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "TimelineAudio")

    /// The format the models read.
    static let timelineFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )

    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    /// Returns the buffer as 16 kHz mono samples, or nil if it cannot be converted.
    func samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, buffer.format.channelCount > 0,
              let timelineFormat = Self.timelineFormat
        else { return nil }

        if buffer.format == timelineFormat, let channelData = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        if converter == nil || converterInputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: timelineFormat) else { return nil }
            converter = made
            converterInputFormat = buffer.format
        }
        guard let converter, buffer.format.sampleRate > 0 else { return nil }

        // Capacity is sized from the rate ratio, plus a margin: a resampler carries state between
        // calls and can return slightly more frames than the ratio alone predicts, and a buffer one
        // frame too small makes it stop early.
        let ratio = timelineFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(frameCount) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: timelineFormat, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if supplied {
                statusPointer.pointee = .noDataNow
                return nil
            }
            supplied = true
            statusPointer.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            logger.warning(
                "Timeline conversion failed: \(conversionError?.localizedDescription ?? "unknown", privacy: .public)"
            )
            return nil
        }
        guard output.frameLength > 0, let channelData = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(output.frameLength)))
    }

    /// Forgets the resampler. Use when capture resumes after a gap: the converter carries state
    /// across calls, and that state does not describe the audio on the other side of a pause.
    func reset() {
        converter = nil
        converterInputFormat = nil
    }
}
