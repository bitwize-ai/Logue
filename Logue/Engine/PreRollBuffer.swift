import AVFoundation
import Foundation

/// A short rolling window of the most recent microphone audio.
///
/// Voice activity is recognised a moment after speech starts, so a transcriber fed only from the
/// moment of recognition receives every utterance with its first consonant already gone. Holding
/// the last fraction of a second and releasing it when the gate opens gives the word back its
/// beginning.
struct PreRollBuffer {
    let maxDuration: TimeInterval

    private var buffers: [AVAudioPCMBuffer] = []
    private(set) var duration: TimeInterval = 0

    init(maxDuration: TimeInterval) {
        self.maxDuration = maxDuration
    }

    mutating func append(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 0, buffer.frameLength > 0 else { return }
        buffers.append(buffer)
        duration += Double(buffer.frameLength) / rate

        // Never drop the only buffer held. One longer than the whole window is still the audio that
        // opened the gate, and discarding it would lose the speech this exists to preserve.
        while duration > maxDuration, buffers.count > 1, let oldest = buffers.first {
            let oldestRate = oldest.format.sampleRate
            buffers.removeFirst()
            guard oldestRate > 0 else { continue }
            duration -= Double(oldest.frameLength) / oldestRate
        }
    }

    mutating func drain() -> [AVAudioPCMBuffer] {
        let held = buffers
        buffers.removeAll(keepingCapacity: true)
        duration = 0
        return held
    }

    mutating func removeAll() {
        buffers.removeAll(keepingCapacity: false)
        duration = 0
    }
}
