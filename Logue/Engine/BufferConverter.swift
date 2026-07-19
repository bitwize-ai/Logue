@preconcurrency import AVFoundation
import Foundation
import os

/// Converts audio buffers between formats for SpeechAnalyzer compatibility.
/// Adapted from SwiftScribe's BufferConversion pattern.
class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?
    /// Cached sample rates to detect format changes without relying on AVAudioFormat equality
    /// (AVAudioFormat instances from buffer.format can compare unequal despite identical parameters).
    private var cachedInputSampleRate: Double = 0
    private var cachedInputChannelCount: UInt32 = 0
    private var cachedOutputSampleRate: Double = 0
    /// Reusable output buffer — avoids per-callback allocation when frame capacity is stable.
    private var cachedOutputBuffer: AVAudioPCMBuffer?
    /// Reusable flag for the converter's input callback — avoids allocating a lock per call.
    private let bufferProcessedFlag = OSAllocatedUnfairLock(initialState: false)

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat.sampleRate != format.sampleRate
            || inputFormat.channelCount != format.channelCount
            || inputFormat.commonFormat != format.commonFormat
        else {
            return buffer
        }

        // Recreate converter only when format parameters actually change
        if converter == nil
            || cachedInputSampleRate != inputFormat.sampleRate
            || cachedInputChannelCount != inputFormat.channelCount
            || cachedOutputSampleRate != format.sampleRate
        {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
            cachedInputSampleRate = inputFormat.sampleRate
            cachedInputChannelCount = inputFormat.channelCount
            cachedOutputSampleRate = format.sampleRate
            cachedOutputBuffer = nil // invalidate cached buffer on format change
        }

        guard let converter else {
            throw Error.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))

        // Reuse output buffer when frame capacity hasn't changed
        let conversionBuffer: AVAudioPCMBuffer
        if let cached = cachedOutputBuffer, cached.frameCapacity >= frameCapacity {
            cached.frameLength = 0 // reset for fresh conversion
            conversionBuffer = cached
        } else {
            guard let newBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: frameCapacity
            )
            else {
                throw Error.failedToCreateConversionBuffer
            }
            cachedOutputBuffer = newBuffer
            conversionBuffer = newBuffer
        }

        converter.reset()

        var nsError: NSError?
        // Reset the flag for this conversion cycle
        bufferProcessedFlag.withLock { $0 = false }

        let status = converter.convert(to: conversionBuffer, error: &nsError) { [bufferProcessedFlag] _, inputStatusPointer in
            let wasProcessed = bufferProcessedFlag.withLock { bufferProcessed in
                let wasProcessed = bufferProcessed
                bufferProcessed = true
                return wasProcessed
            }
            inputStatusPointer.pointee = wasProcessed ? .noDataNow : .haveData
            return wasProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}
