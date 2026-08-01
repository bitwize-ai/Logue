import AVFoundation
import Foundation

/// Reads an audio file as 16 kHz mono Float32, a chunk at a time.
///
/// The post-recording models want the whole recording, but a long meeting does not fit in memory —
/// four hours of 16 kHz Float32 is close to a gigabyte, and that is before the models allocate
/// anything. Reading in chunks keeps what is resident down to one chunk however long the recording
/// is, which is what lets a recording of any length be processed at all.
///
/// It is an iterator rather than a callback so that async consumers stay streaming too: a model that
/// has to be awaited per chunk would otherwise have to collect the chunks up front, which is the
/// whole problem again.
struct AudioFileChunkReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let sourceFormat: AVAudioFormat
    private let target: AVAudioFormat
    private let sourceChunkFrames: AVAudioFrameCount
    private let outputCapacity: AVAudioFrameCount
    private var producedSamples = 0
    private var drained = false

    init(url: URL, chunkSeconds: Double, sampleRate: Double) throws {
        guard chunkSeconds > 0, sampleRate > 0 else { throw AudioFileChunkReaderError.unsupportedFormat }
        file = try AVAudioFile(forReading: url)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        else {
            throw AudioFileChunkReaderError.unsupportedFormat
        }
        self.target = target

        sourceFormat = file.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw AudioFileChunkReaderError.unsupportedFormat
        }
        converter.primeMethod = .none
        self.converter = converter

        // Read in source frames; the converted chunk lands close to `chunkSeconds` at the target rate.
        sourceChunkFrames = AVAudioFrameCount(max(1, chunkSeconds * sourceFormat.sampleRate))
        let ratio = sampleRate / sourceFormat.sampleRate
        outputCapacity = AVAudioFrameCount((Double(sourceChunkFrames) * ratio).rounded(.up) + 1024)
    }

    /// The next chunk and the position it starts at, in samples at the target rate, or nil at the end.
    mutating func next() throws -> (samples: [Float], offset: Int)? {
        while file.framePosition < file.length {
            guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceChunkFrames) else {
                throw AudioFileChunkReaderError.allocationFailed
            }
            try file.read(into: input, frameCount: sourceChunkFrames)
            guard input.frameLength > 0 else { break }

            guard let samples = try convert(feeding: input), !samples.isEmpty else { continue }
            let offset = producedSamples
            producedSamples += samples.count
            return (samples, offset)
        }

        // Drain whatever the converter is still holding. It buffers a little to do its work, so
        // without this the last few milliseconds of every recording are quietly dropped.
        guard !drained else { return nil }
        drained = true
        guard let tail = try? convert(feeding: nil), !tail.isEmpty else { return nil }
        let offset = producedSamples
        producedSamples += tail.count
        return (tail, offset)
    }

    /// Runs one buffer through the converter, or flushes it when `input` is nil.
    private func convert(feeding input: AVAudioPCMBuffer?) throws -> [Float]? {
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else {
            throw AudioFileChunkReaderError.allocationFailed
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPtr in
            guard let input, !consumed else {
                statusPtr.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return input
        }
        if status == .error {
            throw conversionError ?? AudioFileChunkReaderError.conversionFailed
        }
        guard let channel = output.floatChannelData, output.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    // MARK: - Convenience

    /// Calls `onChunk` with successive chunks of the file, converted to `sampleRate` mono Float32.
    /// The second argument is the chunk's start position in samples, for putting its results back on
    /// the meeting's timeline.
    static func read(
        _ url: URL,
        chunkSeconds: Double,
        sampleRate: Double,
        onChunk: ([Float], Int) throws -> Void
    ) throws {
        var reader = try AudioFileChunkReader(url: url, chunkSeconds: chunkSeconds, sampleRate: sampleRate)
        while let chunk = try reader.next() {
            try onChunk(chunk.samples, chunk.offset)
        }
    }

    /// How long an audio file runs, or nil if it cannot be read.
    static func duration(of url: URL) -> TimeInterval? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.fileFormat.sampleRate > 0 else { return nil }
            return TimeInterval(file.length) / file.fileFormat.sampleRate
        } catch {
            return nil
        }
    }
}

enum AudioFileChunkReaderError: Error {
    case unsupportedFormat
    case allocationFailed
    case conversionFailed
}
