import Foundation
@testable import Logue
import Testing

@Suite("Session audio timeline mixing")
struct AudioTimelineMixerTests {
    // MARK: - Helpers

    private let rate: Double = 16000

    private func mixer(seconds: Double = 60) -> AudioTimelineMixer {
        AudioTimelineMixer(sampleRate: rate, capacity: Int(rate * seconds))
    }

    private func tone(_ value: Float, seconds: Double) -> [Float] {
        [Float](repeating: value, count: Int(rate * seconds))
    }

    // MARK: - Single source

    @Test("One source lands end to end, exactly as appending would")
    func singleSourceIsContiguous() {
        var mix = mixer()
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(0.5, seconds: 1), from: .system)
        mix.write(tone(0.25, seconds: 1), from: .system)

        #expect(mix.samples.count == Int(rate * 2))
        #expect(mix.samples[0] == 0.5)
        #expect(mix.samples[Int(rate) + 10] == 0.25)
        #expect(mix.duration == 2)
    }

    @Test("A source that never declares itself writes from the end of the timeline")
    func undeclaredSourceAppends() {
        var mix = mixer()
        mix.write(tone(0.5, seconds: 1), from: .system)

        #expect(mix.samples.count == Int(rate))
    }

    // MARK: - Two sources

    @Test("Two sources share the timeline instead of doubling its length")
    func concurrentSourcesDoNotStackUp() {
        var mix = mixer()
        mix.beginSource(.system, atSessionTime: 0)
        mix.beginSource(.microphone, atSessionTime: 0)

        for _ in 0 ..< 10 {
            mix.write(tone(0.1, seconds: 1), from: .system)
            mix.write(tone(0.2, seconds: 1), from: .microphone)
        }

        // Ten seconds of meeting, from twenty seconds of delivered audio.
        #expect(mix.samples.count == Int(rate * 10))
        #expect(mix.duration == 10)
    }

    @Test("Overlapping audio is summed, not overwritten")
    func overlappingAudioIsSummed() {
        var mix = mixer()
        mix.beginSource(.system, atSessionTime: 0)
        mix.beginSource(.microphone, atSessionTime: 0)
        mix.write(tone(0.25, seconds: 1), from: .system)
        mix.write(tone(0.5, seconds: 1), from: .microphone)

        #expect(mix.samples[0] == 0.75)
    }

    @Test("Simultaneous loud speakers clamp instead of wrapping")
    func summedAudioIsClamped() {
        var mix = mixer()
        mix.beginSource(.system, atSessionTime: 0)
        mix.beginSource(.microphone, atSessionTime: 0)
        mix.write(tone(0.9, seconds: 1), from: .system)
        mix.write(tone(0.9, seconds: 1), from: .microphone)
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(-2.0, seconds: 1), from: .system)

        #expect(mix.samples.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test("A source starting mid-session lands at the time it started, not at zero")
    func lateSourceIsPlacedAtItsStart() {
        var mix = mixer()
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(0.4, seconds: 10), from: .system)

        mix.beginSource(.microphone, atSessionTime: 5)
        mix.write(tone(0.1, seconds: 1), from: .microphone)

        #expect(mix.samples[Int(rate * 2)] == 0.4) // before the mic joined
        #expect(mix.samples[Int(rate * 5) + 10] == Float(0.5)) // mixed with the mic
        #expect(mix.samples.count == Int(rate * 10))
    }

    @Test("A source that stops and resumes is re-placed rather than rewinding to zero")
    func resumedSourceIsRePlaced() {
        var mix = mixer()
        mix.beginSource(.microphone, atSessionTime: 0)
        mix.write(tone(0.3, seconds: 2), from: .microphone)

        // Device clocks restart from zero on a toggle; the session says where the audio belongs.
        mix.beginSource(.microphone, atSessionTime: 8)
        mix.write(tone(0.6, seconds: 1), from: .microphone)

        #expect(mix.samples[10] == 0.3)
        #expect(mix.samples[Int(rate * 5)] == 0) // the gap it was muted for
        #expect(mix.samples[Int(rate * 8) + 10] == 0.6)
    }

    // MARK: - Capacity

    @Test("Audio past capacity is dropped and reported, not grown into")
    func dropsPastCapacity() {
        var mix = mixer(seconds: 5)
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(0.5, seconds: 4), from: .system)
        #expect(!mix.didDropAudio)
        #expect(mix.heardDuration == nil)

        mix.write(tone(0.5, seconds: 4), from: .system)
        #expect(mix.didDropAudio)
        #expect(mix.samples.count == Int(rate * 5))
        #expect(mix.heardDuration == 5)
    }

    @Test("Writes after capacity is reached stay dropped")
    func staysDroppedOnceFull() {
        var mix = mixer(seconds: 2)
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(0.5, seconds: 3), from: .system)
        mix.write(tone(0.5, seconds: 3), from: .system)

        #expect(mix.samples.count == Int(rate * 2))
        #expect(mix.didDropAudio)
    }

    @Test("Capacity is a share of physical memory, floored and capped")
    func capacityScalesWithMemory() {
        let gb: UInt64 = 1024 * 1024 * 1024
        let seconds = { (memory: UInt64) -> Double in
            Double(AudioTimelineMixer.capacity(forPhysicalMemory: memory, sampleRate: 16000)) / 16000
        }

        // 8 GB → 512 MB → ~2.3 hours; 16 GB → the 1 GB cap → ~4.6 hours.
        #expect(seconds(8 * gb) > 8000 && seconds(8 * gb) < 8500)
        #expect(seconds(16 * gb) > 16000 && seconds(16 * gb) < 17000)
        // A large machine is capped, a small one floored — neither runs away.
        #expect(seconds(64 * gb) == seconds(16 * gb))
        #expect(seconds(1 * gb) > 4000)
        // Every supported Mac gets at least an hour of batch-quality processing.
        #expect(seconds(8 * gb) > 3600)
    }

    // MARK: - Clearing

    @Test("Taking the timeline resets it for the next session")
    func takeResets() {
        var mix = mixer(seconds: 2)
        mix.beginSource(.system, atSessionTime: 0)
        mix.write(tone(0.5, seconds: 3), from: .system)

        let taken = mix.take()

        #expect(taken.count == Int(rate * 2))
        #expect(mix.isEmpty)
        #expect(!mix.didDropAudio)
        #expect(mix.heardDuration == nil)
    }
}
