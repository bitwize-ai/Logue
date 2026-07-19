import SwiftUI

/// Hover-revealed action toolbar. Used on message rows, code blocks, and
/// any other surface that needs secondary actions without cluttering the
/// resting state.
///
/// Use this instead of right-click menus for primary actions — consumer
/// apps surface "Copy", "Regenerate", etc. on hover so users can find them
/// without learning a context-menu vocabulary.
///
/// ```swift
/// HoverToolbar(items: [
///     .init(icon: "doc.on.doc", help: "Copy") { copy() },
///     .init(icon: "arrow.clockwise", help: "Regenerate") { regen() },
/// ])
/// ```
struct HoverToolbar: View {
    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let help: String
        var role: ButtonRole?
        let action: () -> Void
    }

    let items: [Item]
    var alignment: HorizontalAlignment = .trailing

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.help)
                .accessibilityLabel(item.help)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        .opacity(isHovered ? 1 : 0)
        .animation(Motion.snappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Reveal-on-hover container

/// Convenience wrapper that reveals a toolbar overlay on hover.
///
/// ```swift
/// MessageBubble(...)
///     .hoverToolbar(alignment: .topTrailing) {
///         HoverToolbar(items: [...])
///     }
/// ```
struct HoverToolbarModifier<Toolbar: View>: ViewModifier {
    let alignment: Alignment
    let toolbar: () -> Toolbar
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                toolbar()
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    .animation(Motion.snappy, value: isHovered)
                    .padding(6)
            }
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverToolbar(
        alignment: Alignment = .topTrailing,
        @ViewBuilder _ toolbar: @escaping () -> some View
    ) -> some View {
        modifier(HoverToolbarModifier(alignment: alignment, toolbar: toolbar))
    }
}
