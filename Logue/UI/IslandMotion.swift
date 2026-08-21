import SwiftUI

/// Which of the island's animations survive Reduce Motion, and what replaces the rest.
///
/// The island is the most animated surface in Logue: it slides in over another app, its panel
/// springs open on the first message, chips scale in and out, and two indicators pulse
/// forever. None of it consulted Accessibility → Display → Reduce motion, so a user who has
/// asked the system for less movement got the most of it here.
///
/// The distinction the policy turns on is **decoration versus information**. A spring, a
/// slide and a scale say nothing that the layout does not already say, so they go. A pulsing
/// dot is different: it is the only thing on screen saying the agent is still working. It is
/// still removed — but only because the row it sits in also carries the words "Thinking…",
/// so the information survives without it. Removing the pulse from somewhere with no such
/// text would be removing the signal, not the decoration.
///
/// The level meter is deliberately untouched. Its movement *is* the reading — a still meter
/// is not a calmer meter, it is a broken one.
enum IslandMotion {
    /// How something arriving or leaving should be drawn.
    enum Entrance: Equatable {
        /// Slides from an edge as it fades.
        case slideAndFade
        /// Fades only. A cross-fade is motion the setting permits, and dropping the
        /// animation entirely would make things appear as jump cuts.
        case fadeOnly
    }

    static func entrance(reduceMotion: Bool) -> Entrance {
        reduceMotion ? .fadeOnly : .slideAndFade
    }

    /// Whether an indicator may pulse forever.
    ///
    /// Only ever false where the thing it decorates is also stated in words.
    static func allowsPulse(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// The animation for a layout change — a panel opening, a chip row appearing.
    ///
    /// `nil` rather than a shorter spring: a spring is the movement, and making it quick
    /// makes it a flinch. The content still cross-fades through its transition.
    static func layout(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// The animation for a small control changing state — the Return hint, a mode toggling.
    static func control(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    /// The transition for something entering or leaving the island.
    static func transition(reduceMotion: Bool, edge: Edge = .bottom) -> AnyTransition {
        switch entrance(reduceMotion: reduceMotion) {
        case .slideAndFade: .move(edge: edge).combined(with: .opacity)
        case .fadeOnly: .opacity
        }
    }
}
