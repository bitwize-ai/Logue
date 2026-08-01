import AVFoundation
import Foundation

/// Reads an audio file as 16 kHz mono Float32, a chunk at a time.
///
/// The post-recording models want the whole recording, but a long meeting does not fit in memory —
/// four hours of 16 kHz Float32 is close to a gigabyte, and that is before the models allocate
/// anything. Reading in chunks keeps what is resident down to one chunk however long the recording
/// is, which is what lets a recording of any length be processed at all.
enum AudioFileChunkReader {
    /// Calls `onChunk` with successive chunks of the file, converted to `sampleRate` mono Float32.
    /// The second argument is the chunk's start position in samples, for putting its results back on
    /// the meeting's timeline.
    static func read(
        _ url: URL,
        chunkSeconds: Double,
        sampleRate: Double,
        onChunk: ([Float], Int) throws -> Void
    ) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, chunkSeconds > 0, sampleRate > 0 else { return }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        else {
            throw AudioFileChunkReaderError.unsupportedFormat
        }

        let sourceFormat = file.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw AudioFileChunkReaderError.unsupportedFormat
        }
        converter.primeMethod = .none

        // Read in source frames; the converted chunk lands close to `chunkSeconds` at the target rate.
        let sourceChunkFrames = AVAudioFrameCount(max(1, chunkSeconds * sourceFormat.sampleRate))
        let ratio = sampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(sourceChunkFrames) * ratio).rounded(.up) + 1024)

        var writtenSamples = 0
        while file.framePosition < file.length {
            guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceChunkFrames) else {
                throw AudioFileChunkReaderError.allocationFailed
            }
            try file.read(into: input, frameCount: sourceChunkFrames)
            guard input.frameLength > 0 else { break }

            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else {
                throw AudioFileChunkReaderError.allocationFailed
            }

            var consumed = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, statusPtr in
                if consumed {
                    statusPtr.pointee = .noDataNow
                    return nil
                }
                consumed = true
                statusPtr.pointee = .haveData
                return input
            }
            if status == .error {
                throw conversionError ?? AudioFileChunkReaderError.conversionFailed
            }

            guard let channel = output.floatChannelData, output.frameLength > 0 else { continue }
            let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
            try onChunk(samples, writtenSamples)
            writtenSamples += samples.count
        }
    }
}

enum AudioFileChunkReaderError: Error {
    case unsupportedFormat
    case allocationFailed
    case conversionFailed
}
