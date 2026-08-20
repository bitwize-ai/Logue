import AVFoundation
@testable import Logue
import Testing

/// The conversion that feeds the session timeline.
///
/// The saved recording is written straight from the capture tap, but the models read a 16 kHz mono
/// timeline built by converting those same buffers. A conversion that yields silence therefore
/// produces a perfectly audible recording with an empty transcript — which is exactly what shipped.
@Suite("Timeline audio conversion")
struct TimelineAudioConversionTests {
    /// A one-second tone at `rate`, the shape a capture tap actually delivers.
    private func tone(rate: Double, channels: AVAudioChannelCount = 1) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)
        )
        let frames = AVAudioFrameCount(rate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try #require(buffer.floatChannelData)
        for channel in 0 ..< Int(channels) {
            for frame in 0 ..< Int(frames) {
                data[channel][frame] = 0.5 * sinf(2 * .pi * 440 * Float(frame) / Float(rate))
            }
        }
        return buffer
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let total = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (total / Float(samples.count)).squareRoot()
    }

    @Test("A 48 kHz tone survives conversion to the 16 kHz timeline")
    func resamplesWithoutSilencing() throws {
        let source = try tone(rate: 48000)
        let converted = try #require(TimelineAudioConverter().samples(from: source))

        #expect(converted.isEmpty == false, "conversion produced no samples at all")
        #expect(
            rms(converted) > 0.01,
            "conversion produced silence — the recording is audible but the models hear nothing"
        )
    }

    @Test("A stereo tap is folded to mono without silencing")
    func stereoSurvives() throws {
        let source = try tone(rate: 48000, channels: 2)
        let converted = try #require(TimelineAudioConverter().samples(from: source))
        #expect(rms(converted) > 0.01)
    }

    @Test("Audio already at the timeline's format passes straight through")
    func matchingFormatIsUntouched() throws {
        let source = try tone(rate: 16000)
        let converted = try #require(TimelineAudioConverter().samples(from: source))
        #expect(converted.count == 16000)
        #expect(rms(converted) > 0.01)
    }

    @Test("Successive buffers keep producing audio, not just the first")
    func repeatedConversionsStayAudible() throws {
        let converter = TimelineAudioConverter()
        for index in 0 ..< 5 {
            let converted = try #require(try converter.samples(from: tone(rate: 48000)))
            #expect(rms(converted) > 0.01, "buffer \(index) came back silent")
        }
    }
}
