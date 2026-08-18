import Foundation
@testable import Logue
import Testing

@Suite("System audio arming")
struct SystemAudioArmingTests {
    // MARK: - Debounce

    @Test("Playback shorter than the debounce does not arm")
    func briefPlaybackDoesNotArm() {
        var debounce = PlaybackArmingDebounce(debounce: 1.0)
        #expect(debounce.observe(isPlaying: true, at: 0) == false)
        #expect(debounce.observe(isPlaying: false, at: 0.4) == false)
        #expect(debounce.hasArmed == false)
    }

    @Test("Playback sustained past the debounce arms once")
    func sustainedPlaybackArms() {
        var debounce = PlaybackArmingDebounce(debounce: 1.0)
        #expect(debounce.observe(isPlaying: true, at: 0) == false)
        #expect(debounce.observe(isPlaying: true, at: 1.5) == true)
        #expect(debounce.hasArmed)
    }

    @Test("Arming happens once and never again for the session")
    func armsOnlyOnce() {
        var debounce = PlaybackArmingDebounce(debounce: 1.0)
        _ = debounce.observe(isPlaying: true, at: 0)
        #expect(debounce.observe(isPlaying: true, at: 2) == true)
        // Playback stopping and restarting must not re-arm: the tap is already running.
        #expect(debounce.observe(isPlaying: false, at: 3) == false)
        #expect(debounce.observe(isPlaying: true, at: 4) == false)
        #expect(debounce.observe(isPlaying: true, at: 10) == false)
    }

    @Test("A gap in playback restarts the debounce window")
    func gapRestartsTheWindow() {
        var debounce = PlaybackArmingDebounce(debounce: 1.0)
        #expect(debounce.observe(isPlaying: true, at: 0) == false)
        #expect(debounce.observe(isPlaying: false, at: 0.5) == false)
        // A new burst starts counting from scratch, so 1.2s after the *first* burst is not enough.
        #expect(debounce.observe(isPlaying: true, at: 0.6) == false)
        #expect(debounce.observe(isPlaying: true, at: 1.2) == false)
        #expect(debounce.observe(isPlaying: true, at: 1.7) == true)
    }
}
