import Foundation
import Testing

@testable import Logue

/// The island's surface rule, which decides whether the desktop shows through and how hard
/// the veil over it has to work.
///
/// Worth pinning because every case here is invisible in the one configuration a developer
/// actually runs — transparency on, contrast standard, a dark wallpaper. The settings that
/// break it are ones you have to go and turn on.
@Suite("IslandSurface")
struct IslandSurfaceTests {
    private func treatment(
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) -> IslandSurface.Treatment {
        IslandSurface.treatment(
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
    }

    // MARK: - Reduce transparency

    @Test("Reduce transparency stops the island being glass at all")
    func reducedTransparencyIsOpaque() {
        // Not "less transparent" — the setting is a request for no see-through surfaces, and
        // a panel that is merely 70% opaque still shows the desktop moving underneath it.
        let reduced = treatment(reduceTransparency: true)
        #expect(reduced.usesMaterial == false)
        #expect(reduced.scrimOpacity == 1)
    }

    @Test("An opaque island casts no shadow")
    func reducedTransparencyDropsTheShadow() {
        // A soft shadow is the same visual effect the setting exists to remove, so keeping it
        // under an opaque panel honours the letter of the setting and not the point of it.
        #expect(treatment(reduceTransparency: true).shadowOpacity == 0)
        #expect(treatment().shadowOpacity > 0)
    }

    @Test("Glass is the default")
    func defaultIsGlass() {
        let standard = treatment()
        #expect(standard.usesMaterial)
        #expect(standard.scrimOpacity < 1, "the desktop has to show through for it to be glass")
    }

    // MARK: - The scrim floor

    @Test("Every treatment keeps the scrim above the floor")
    func scrimNeverFallsBelowTheFloor() {
        // The failure this guards: glass with no veil over a white document is white text on
        // a white panel. Delete the scrim from `treatment` and this goes red for every case.
        for reduceTransparency in [false, true] {
            for increaseContrast in [false, true] {
                let result = treatment(
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )
                #expect(
                    result.scrimOpacity >= IslandSurface.minimumScrimOpacity,
                    "transparency=\(reduceTransparency) contrast=\(increaseContrast)"
                )
            }
        }
    }

    // MARK: - Increase contrast

    @Test("Increase contrast never lightens anything")
    func increasedContrastOnlyEverDeepens() {
        // Stated as a comparison rather than as numbers so that retuning the palette cannot
        // quietly invert the setting — which is the mistake that would be hardest to notice,
        // since the island still looks fine to anyone who has contrast off.
        for reduceTransparency in [false, true] {
            let standard = treatment(reduceTransparency: reduceTransparency)
            let increased = treatment(reduceTransparency: reduceTransparency, increaseContrast: true)
            #expect(increased.scrimOpacity >= standard.scrimOpacity)
            #expect(increased.strokeOpacity > standard.strokeOpacity)
        }
    }

    @Test("The edge is always drawn")
    func theEdgeIsAlwaysVisible() {
        // Against a dark desktop an island with no stroke has no boundary and reads as a hole
        // cut in the screen rather than a panel floating over it.
        for reduceTransparency in [false, true] {
            for increaseContrast in [false, true] {
                let result = treatment(
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )
                #expect(result.strokeOpacity > 0)
            }
        }
    }

    // MARK: - Bounds

    @Test("No opacity is outside 0...1")
    func opacitiesAreInRange() {
        for reduceTransparency in [false, true] {
            for increaseContrast in [false, true] {
                let result = treatment(
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )
                #expect((0 ... 1).contains(result.scrimOpacity))
                #expect((0 ... 1).contains(result.strokeOpacity))
                #expect((0 ... 1).contains(result.shadowOpacity))
            }
        }
    }
}
