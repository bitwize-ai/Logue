import SwiftUI
import Testing

@testable import Logue

/// What Reduce Motion does to the island.
///
/// The island is the most animated surface in Logue and consulted the setting nowhere, so a
/// user who asked the system for less movement got the most of it here.
@Suite("IslandMotion")
struct IslandMotionTests {
    @Test("Reduce Motion turns movement into a fade")
    func movementBecomesAFade() {
        // A cross-fade is motion the setting permits. Dropping the transition altogether
        // would make panels appear as jump cuts, which is not what was asked for.
        #expect(IslandMotion.entrance(reduceMotion: true) == .fadeOnly)
        #expect(IslandMotion.entrance(reduceMotion: false) == .slideAndFade)
    }

    @Test("Reduce Motion stops the pulses")
    func pulsesStop() {
        // Safe only because every place the island pulses also says what is happening in
        // words. A pulse with no such text is the signal, not the decoration.
        #expect(IslandMotion.allowsPulse(reduceMotion: true) == false)
        #expect(IslandMotion.allowsPulse(reduceMotion: false))
    }

    @Test("A spring is removed rather than shortened")
    func springsAreRemovedNotHurried() {
        // A spring *is* the movement; making it quick makes it a flinch rather than calm.
        #expect(IslandMotion.layout(reduceMotion: true) == nil)
        #expect(IslandMotion.layout(reduceMotion: false) != nil)
    }

    @Test("Control changes stop animating too")
    func controlAnimationsStop() {
        #expect(IslandMotion.control(reduceMotion: true) == nil)
        #expect(IslandMotion.control(reduceMotion: false) != nil)
    }

    @Test("Nothing animates at all when motion is reduced")
    func nothingSurvivesUnnoticed() {
        // A sweep, so a new animation added to the policy without a reduced branch fails
        // here rather than shipping.
        #expect(IslandMotion.layout(reduceMotion: true) == nil)
        #expect(IslandMotion.control(reduceMotion: true) == nil)
        #expect(IslandMotion.allowsPulse(reduceMotion: true) == false)
        #expect(IslandMotion.entrance(reduceMotion: true) == .fadeOnly)
    }

    @Test("Ordinary settings keep every animation")
    func normalSettingsAreUnchanged() {
        // The other half: this must not quietly flatten the island for everyone.
        #expect(IslandMotion.layout(reduceMotion: false) != nil)
        #expect(IslandMotion.control(reduceMotion: false) != nil)
        #expect(IslandMotion.allowsPulse(reduceMotion: false))
        #expect(IslandMotion.entrance(reduceMotion: false) == .slideAndFade)
    }
}
