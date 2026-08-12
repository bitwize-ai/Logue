import AVFoundation
import Foundation
@testable import Logue
import Testing

/// The saved file has to *be* the meeting's timeline, and a single source that was muted or joined
/// late records a file that is shorter than the meeting. These check the splice that restores the
/// gaps — losslessly, because paying an AAC encode to insert silence would both cost a minute at the
/// end of a long recording and hand the transcriber a lossy copy of audio we already have clean.
@Suite("Splicing a muted recording back onto the meeting's timeline")
@MainActor
struct RecordingSpliceTests {
    private typealias Placement = CaptureSegmentTimeline.Placement

    private let rate: Double = 16000

    private func temporaryURL(_ ext: String = "wav") -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension(ext)
    }

    /// Writes `seconds` of a constant tone, so silence and audio are trivially distinguishable.
    private func writeTone(_ value: Float, seconds: Double, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false
        )
        else { throw AudioFileChunkReaderError.unsupportedFormat }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        var written = 0
        let total = Int(seconds * rate)
        while written < total {
            let count = min(16000, total - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
            else { throw AudioFileChunkReaderError.allocationFailed }
            buffer.frameLength = AVAudioFrameCount(count)
            if let channel = buffer.floatChannelData {
                for i in 0 ..< count {
                    channel[0][i] = value
                }
            }
            try file.write(from: buffer)
            written += count
        }
    }

    private func samples(of url: URL) throws -> [Float] {
        var out: [Float] = []
        try AudioFileChunkReader.read(url, chunkSeconds: 5, sampleRate: rate) { chunk, _ in
            out.append(contentsOf: chunk)
        }
        return out
    }

    // MARK: - Routing

    @Test("A source that ran throughout is saved without being rewritten")
    func unbrokenSourceIsMovedNotComposed() throws {
        let source = temporaryURL()
        defer { try? FileManager.default.removeItem(at: source) }
        try writeTone(0.5, seconds: 3, to: source)

        var sources = RecordingSessionManager.CaptureSources()
        sources.micURL = source
        sources.micPlacements = [Placement(fileStart: 0, duration: 3, sessionStart: 0)]

        #expect(!sources.needsComposing)
        #expect(sources.soleSource?.url == source)
    }

    // MARK: - Splicing

    @Test("A late join is placed at the time it started, with silence before it")
    func lateJoinGetsLeadingSilence() async throws {
        let source = temporaryURL()
        defer { try? FileManager.default.removeItem(at: source) }
        try writeTone(0.5, seconds: 2, to: source)

        let meetingID = UUID()
        var sources = RecordingSessionManager.CaptureSources()
        sources.micURL = source
        sources.micPlacements = [Placement(fileStart: 0, duration: 2, sessionStart: 4)]

        let saved = await RecordingSessionManager.shared.persistRecordingAudio(
            sources: sources, meetingID: meetingID
        )
        let url = try #require(saved.url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(saved.describesSessionTimeline)
        let out = try samples(of: url)
        // Six seconds of meeting from two seconds of audio.
        #expect(abs(Double(out.count) / rate - 6) < 0.1)
        #expect(out[Int(rate * 1)] == 0) // before the mic joined
        #expect(abs(out[Int(rate * 5)] - 0.5) < 0.01) // after it joined
    }

    @Test("A mute becomes silence, and audio after it is not pulled early")
    func muteIsRestoredAsSilence() async throws {
        let source = temporaryURL()
        defer { try? FileManager.default.removeItem(at: source) }
        // Four seconds recorded across two activations, with a four-second mute between them.
        try writeTone(0.5, seconds: 4, to: source)

        let meetingID = UUID()
        var sources = RecordingSessionManager.CaptureSources()
        sources.micURL = source
        sources.micPlacements = [
            Placement(fileStart: 0, duration: 2, sessionStart: 0),
            Placement(fileStart: 2, duration: 2, sessionStart: 6),
        ]

        let saved = await RecordingSessionManager.shared.persistRecordingAudio(
            sources: sources, meetingID: meetingID
        )
        let url = try #require(saved.url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(saved.describesSessionTimeline)
        let out = try samples(of: url)
        #expect(abs(Double(out.count) / rate - 8) < 0.1)
        #expect(abs(out[Int(rate * 1)] - 0.5) < 0.01) // first activation
        #expect(out[Int(rate * 4)] == 0) // the muted stretch
        #expect(abs(out[Int(rate * 7)] - 0.5) < 0.01) // second activation, not pulled early
    }

    @Test("The splice keeps PCM rather than re-encoding")
    func spliceStaysLossless() async throws {
        let source = temporaryURL()
        defer { try? FileManager.default.removeItem(at: source) }
        try writeTone(0.25, seconds: 2, to: source)

        let meetingID = UUID()
        var sources = RecordingSessionManager.CaptureSources()
        sources.micURL = source
        sources.micPlacements = [
            Placement(fileStart: 0, duration: 1, sessionStart: 0),
            Placement(fileStart: 1, duration: 1, sessionStart: 3),
        ]

        let saved = await RecordingSessionManager.shared.persistRecordingAudio(
            sources: sources, meetingID: meetingID
        )
        let url = try #require(saved.url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Same container as the source, and the samples come back exactly — an AAC round-trip
        // would neither keep the extension nor return the value untouched.
        #expect(url.pathExtension == "wav")
        let out = try samples(of: url)
        #expect(out[Int(rate / 2)] == 0.25)
    }
}
