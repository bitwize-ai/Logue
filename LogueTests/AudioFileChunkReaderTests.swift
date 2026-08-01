import AVFoundation
import Foundation
@testable import Logue
import Testing

@Suite("Reading a recording back in chunks")
struct AudioFileChunkReaderTests {
    // MARK: - Helpers

    /// Writes a mono WAV of `seconds` at `sampleRate` whose samples encode their own position, so a
    /// reader that drops, repeats or reorders audio cannot pass.
    private func writeRamp(seconds: Double, sampleRate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )
        else {
            throw AudioFileChunkReaderError.unsupportedFormat
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let total = Int(seconds * sampleRate)
        let blockSize = 16000
        var written = 0
        while written < total {
            let count = min(blockSize, total - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw AudioFileChunkReaderError.allocationFailed
            }
            buffer.frameLength = AVAudioFrameCount(count)
            if let channel = buffer.floatChannelData {
                for i in 0 ..< count {
                    // A slow sawtooth: distinct per position, and stable through float32 round-trip.
                    channel[0][i] = Float((written + i) % 1000) / 1000
                }
            }
            try file.write(from: buffer)
            written += count
        }
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("wav")
    }

    // MARK: - Tests

    @Test("Chunks cover the whole file exactly once, in order")
    func chunksCoverTheFileInOrder() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 12, sampleRate: 16000, to: url)

        var offsets: [Int] = []
        var recovered: [Float] = []
        try AudioFileChunkReader.read(url, chunkSeconds: 5, sampleRate: 16000) { samples, offset in
            offsets.append(offset)
            recovered.append(contentsOf: samples)
        }

        #expect(recovered.count == 12 * 16000)
        // Each chunk is handed the position it starts at, and they run consecutively.
        #expect(offsets.first == 0)
        for (index, offset) in offsets.enumerated() where index > 0 {
            #expect(offset > offsets[index - 1])
        }
        // The ramp comes back in the order it was written.
        #expect(abs(recovered[0] - 0) < 0.001)
        #expect(abs(recovered[500] - 0.5) < 0.001)
        #expect(abs(recovered[16000 * 7 + 250] - 0.25) < 0.001)
    }

    @Test("A file at another sample rate is resampled to the model's rate")
    func resamplesToTargetRate() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 4, sampleRate: 48000, to: url)

        var total = 0
        try AudioFileChunkReader.read(url, chunkSeconds: 1, sampleRate: 16000) { samples, _ in
            total += samples.count
        }

        // 4 seconds at 16 kHz, within a buffer's worth of slack for converter edges.
        #expect(abs(total - 4 * 16000) < 2000)
    }

    @Test("A chunk longer than the file yields the file once")
    func chunkLargerThanFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 2, sampleRate: 16000, to: url)

        var chunks = 0
        var total = 0
        try AudioFileChunkReader.read(url, chunkSeconds: 600, sampleRate: 16000) { samples, _ in
            chunks += 1
            total += samples.count
        }

        #expect(chunks == 1)
        #expect(total == 2 * 16000)
    }

    @Test("The converter's tail is drained, so the end of a recording is not dropped")
    func drainsConverterTail() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 3, sampleRate: 44100, to: url)

        var total = 0
        try AudioFileChunkReader.read(url, chunkSeconds: 1, sampleRate: 16000) { samples, _ in
            total += samples.count
        }

        // Within a few milliseconds of three seconds — the resampler's own edge, not a lost chunk.
        #expect(abs(total - 3 * 16000) < 160)
    }

    @Test("Duration is reported without reading the audio")
    func reportsDuration() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 7, sampleRate: 16000, to: url)

        let duration = try #require(AudioFileChunkReader.duration(of: url))
        #expect(abs(duration - 7) < 0.01)
        #expect(AudioFileChunkReader.duration(of: temporaryURL()) == nil)
    }

    @Test("An empty file yields nothing rather than failing")
    func emptyFileYieldsNothing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: 0, sampleRate: 16000, to: url)

        var chunks = 0
        try AudioFileChunkReader.read(url, chunkSeconds: 5, sampleRate: 16000) { _, _ in chunks += 1 }

        #expect(chunks == 0)
    }

    /// Writes a multi-gigabyte fixture, so it is opt-in rather than part of every run.
    @Test(
        "A recording far past the in-memory limit reads back whole, a chunk at a time",
        .enabled(if: ProcessInfo.processInfo.environment["LOGUE_RUN_MULTIHOUR_TESTS"] != nil)
    )
    func multiHourRecordingReadsBackWhole() throws {
        // Six hours — beyond the in-memory timeline on any machine, which is the case that used to
        // stop being processed at all.
        let hours: Double = 6
        let rate: Double = 16000
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeRamp(seconds: hours * 3600, sampleRate: rate, to: url)

        let capacity = AudioTimelineMixer.capacity(
            forPhysicalMemory: ProcessInfo.processInfo.physicalMemory, sampleRate: rate
        )
        let totalSamples = Int(hours * 3600 * rate)
        #expect(totalSamples > capacity) // the recording genuinely does not fit in memory

        var chunks = 0
        var read = 0
        var largestChunk = 0
        var lastOffset = -1
        try AudioFileChunkReader.read(url, chunkSeconds: 30, sampleRate: rate) { samples, offset in
            chunks += 1
            read += samples.count
            largestChunk = max(largestChunk, samples.count)
            #expect(offset > lastOffset)
            lastOffset = offset
        }

        #expect(read == totalSamples)
        #expect(chunks > 700)
        // Nothing bigger than one chunk is ever resident — that is what removes the ceiling.
        #expect(largestChunk <= Int(31 * rate))
        #expect(largestChunk * MemoryLayout<Float>.size < 4 * 1024 * 1024)
    }
}
