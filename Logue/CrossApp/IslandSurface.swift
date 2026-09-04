import Foundation

/// How the Command Center island paints itself over a desktop it knows nothing about.
///
/// The island is the only surface in Logue with no control over its own background. A window
/// sits on the app's own canvas; the island sits on whatever the user happens to have behind
/// it — a white document, a photograph, a video playing at full brightness. So the two things
/// that make a floating panel readable have to be decided rather than picked once and hoped
/// for.
///
/// **Why the prompt pill was a slab.** It used to be filled with a fixed near-opaque dark
/// colour, which is legible everywhere and looks like a rectangle stuck to the screen. The
/// transcript above it used `.ultraThinMaterial` and looked like glass. One island, two
/// materials, and the seam between them visible whenever both were on screen.
///
/// **Why the colour scheme is pinned rather than adaptive.** Every foreground in the island is
/// white — the bubbles, the placeholder, the icons, the chips. `Material` is not: in Light
/// appearance `.ultraThinMaterial` is a light frost, so the transcript rendered white text on
/// a white-ish panel and simply could not be read. Half a palette adapting is worse than none
/// adapting, and this is a HUD over someone else's window rather than a document, so the
/// island commits to dark and every white in it is then correct by construction. That is what
/// makes it legible in *both* system appearances: it does not change with them.
///
/// Kept free of SwiftUI so the matrix below is testable without mounting a view — the same
/// reason `CommandCenterChatRule` is free of AppKit.
enum IslandSurface {
    /// What to paint, for one set of accessibility settings.
    ///
    /// Opacities rather than colours: the colour is the island's, and a rule that returned
    /// `Color` could not be tested without SwiftUI.
    struct Treatment: Equatable {
        /// Whether the desktop is allowed to show through at all.
        let usesMaterial: Bool
        /// The veil laid over the material. This is what buys contrast against a bright
        /// wallpaper; without it, glass alone leaves white text sitting on white.
        let scrimOpacity: Double
        /// The hairline that separates the island from whatever is behind it. Against a
        /// dark desktop the island's edge is otherwise invisible and it reads as a hole.
        let strokeOpacity: Double
        /// Lifts the island off the desktop. Dropped when transparency is reduced, because
        /// a soft shadow under an opaque panel is the effect that setting exists to remove.
        let shadowOpacity: Double
    }

    /// The scrim can never go below this, whatever else is set.
    ///
    /// Glass with no veil is the failure this type exists to prevent: over a white document
    /// `.ultraThinMaterial` is nearly white, and the island's white text disappears into it.
    static let minimumScrimOpacity: Double = 0.22

    /// What the island should paint.
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Settings → Accessibility → Display → Reduce
    ///     transparency. The user has asked for no see-through surfaces, so the island stops
    ///     being glass entirely rather than becoming slightly-less-glass.
    ///   - increaseContrast: Accessibility → Display → Increase contrast. Deepens the veil
    ///     and hardens the edge; it never lightens either.
    static func treatment(
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> Treatment {
        guard !reduceTransparency else {
            // Fully opaque, and the shadow goes with it.
            return Treatment(
                usesMaterial: false,
                scrimOpacity: 1,
                strokeOpacity: increaseContrast ? 0.9 : 0.35,
                shadowOpacity: 0
            )
        }
        return Treatment(
            usesMaterial: true,
            scrimOpacity: increaseContrast ? 0.55 : 0.3,
            strokeOpacity: increaseContrast ? 0.55 : 0.12,
            shadowOpacity: 0.35
        )
    }
}
