import SwiftUI

/// Paints a panel of the island, following `IslandSurface`.
///
/// The rule lives next door, free of SwiftUI, so what to paint is testable; this is only how.
/// Both of the island's panels use it so they cannot drift into two materials again — which
/// is what they had, the pill filled with a fixed colour and the transcript above it frosted.
extension View {
    func islandSurface(cornerRadius: CGFloat) -> some View {
        modifier(IslandSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct IslandSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// The colour the veil is made of — the island's own near-black, which is what the prompt
    /// pill used to be filled with outright.
    private static let base = Color(
        nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )

    private var treatment: IslandSurface.Treatment {
        IslandSurface.treatment(
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased
        )
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if treatment.usesMaterial {
                        shape.fill(.ultraThinMaterial)
                    }
                    // Always drawn. With the material it is the veil that buys contrast over a
                    // bright wallpaper; without it, it is the whole background.
                    shape.fill(Self.base.opacity(treatment.scrimOpacity))
                }
            }
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(treatment.strokeOpacity),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(treatment.shadowOpacity), radius: 30, y: 12)
    }
}

/// Applies a control's name, state and tooltip in one place.
///
/// A modifier rather than three lines at each call site: the failure this box is about is a
/// control that got the tooltip and not the label, which is exactly what happens when the
/// three are written out separately and one is forgotten.
extension View {
    func islandControl(_ control: IslandControlCopy.Control) -> some View {
        accessibilityLabel(control.label)
            .accessibilityValue(control.value ?? "")
            .accessibilityHint(control.hint)
            .help(control.hint)
    }
}
