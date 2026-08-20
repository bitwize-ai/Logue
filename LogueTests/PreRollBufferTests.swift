import AVFoundation
@testable import Logue
import Testing

@Suite("Pre-roll buffer")
struct PreRollBufferTests {
    private func buffer(seconds: Double, sampleRate: Double = 16000) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        )
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        pcm.frameLength = frames
        return pcm
    }

    @Test("Holds audio up to its limit")
    func holdsUpToTheLimit() throws {
        var ring = PreRollBuffer(maxDuration: 0.3)
        try ring.append(buffer(seconds: 0.1))
        try ring.append(buffer(seconds: 0.1))
        #expect(abs(ring.duration - 0.2) < 0.001)
    }

    @Test("Drops the oldest audio past its limit")
    func dropsOldestPastTheLimit() throws {
        var ring = PreRollBuffer(maxDuration: 0.3)
        for _ in 0 ..< 10 {
            try ring.append(buffer(seconds: 0.1))
        }
        #expect(ring.duration <= 0.3 + 0.001, "an unbounded ring would grow for the whole meeting")
    }

    @Test("Draining hands over everything held and empties the ring")
    func drainEmpties() throws {
        var ring = PreRollBuffer(maxDuration: 0.3)
        try ring.append(buffer(seconds: 0.1))
        try ring.append(buffer(seconds: 0.1))
        let drained = ring.drain()
        #expect(drained.count == 2)
        #expect(ring.duration == 0)
    }

    @Test("Draining twice yields nothing the second time")
    func drainingTwiceIsEmpty() throws {
        var ring = PreRollBuffer(maxDuration: 0.3)
        try ring.append(buffer(seconds: 0.1))
        _ = ring.drain()
        #expect(ring.drain().isEmpty, "released audio must not be handed to the transcriber twice")
    }

    @Test("A buffer longer than the whole window is still held")
    func oversizedBufferSurvives() throws {
        var ring = PreRollBuffer(maxDuration: 0.3)
        try ring.append(buffer(seconds: 1.0))
        #expect(ring.drain().count == 1, "dropping it would lose the speech that opened the gate")
    }
}
