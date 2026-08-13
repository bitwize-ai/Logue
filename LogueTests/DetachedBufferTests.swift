import AVFoundation
@testable import Logue
import Testing

@Suite("Detached audio buffers")
struct DetachedBufferTests {
    private func buffer(value: Float, frames: AVAudioFrameCount = 512) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)
        )
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        pcm.frameLength = frames
        let data = try #require(pcm.floatChannelData)
        for frame in 0 ..< Int(frames) {
            data[0][frame] = value
        }
        return pcm
    }

    @Test("A copy keeps its audio after the original is overwritten")
    func survivesTheOriginalBeingReused() throws {
        let original = try buffer(value: 0.5)
        let copy = try #require(original.detachedCopy())

        // Exactly what the audio engine does to a tap buffer once the callback returns.
        let data = try #require(original.floatChannelData)
        for frame in 0 ..< Int(original.frameLength) {
            data[0][frame] = 0
        }

        let copied = try #require(copy.floatChannelData)
        #expect(copied[0][0] == 0.5, "the copy shared memory with the buffer it came from")
        #expect(copied[0][Int(copy.frameLength) - 1] == 0.5)
    }

    @Test("A copy carries the same shape as the original")
    func preservesFormatAndLength() throws {
        let original = try buffer(value: 0.25, frames: 1024)
        let copy = try #require(original.detachedCopy())
        #expect(copy.frameLength == original.frameLength)
        #expect(copy.format == original.format)
    }

    @Test("An empty buffer has nothing to copy")
    func emptyBufferIsRejected() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)
        )
        let empty = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        empty.frameLength = 0
        #expect(empty.detachedCopy() == nil)
    }
}
