import AVFoundation
import Foundation

extension AVAudioPCMBuffer {
    /// An independent copy of this buffer's audio.
    ///
    /// A buffer handed to an `installTap` callback belongs to the audio engine and is valid only for
    /// the duration of that call — the engine reuses the memory behind it immediately afterwards.
    /// Anything that forwards a tap buffer to be read later, on another actor or through a queue,
    /// must copy it first, or it will eventually read whatever the engine has since written there.
    ///
    /// The failure mode is quiet and misleading: the recording written inside the callback is
    /// perfectly audible, while everything downstream sees silence and reports an empty transcript.
    func detachedCopy() -> AVAudioPCMBuffer? {
        guard frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)
        else { return nil }

        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)

        if let source = floatChannelData, let destination = copy.floatChannelData {
            for channel in 0 ..< channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
        if let source = int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0 ..< channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
        if let source = int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0 ..< channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
        return nil
    }
}
