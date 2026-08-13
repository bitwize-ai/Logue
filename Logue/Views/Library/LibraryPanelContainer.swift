import AppKit
import SwiftUI

/// A resizable right panel for a library surface.
///
/// Not `UnifiedSidebarView`: that one always draws a tab strip above its content, which is
/// right for the meeting and document workspaces (six tools each) and noise here, where a
/// surface has one panel. This keeps the same resize behaviour and the same width limits, so
/// the two feel identical to drag, and puts the tool's icon inline with the panel's controls
/// instead of in a strip of one.
struct LibraryPanelContainer<Content: View>: View {
    @Binding var isCollapsed: Bool
    /// Persisted across open/close by the surface that owns it.
    @Binding var width: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.workspaceWidth) private var workspaceWidth

    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?

    private let limit = SidebarWidthLimit.libraryPanel

    /// Wider than the workspace panels' 320 default: these carry a search field, filter
    /// controls and two-line rows, all of which are cramped at that width.
    static var defaultWidth: CGFloat {
        480
    }

    /// Clamped to what the window currently allows, held separately from `width` so shrinking
    /// the window narrows the panel on screen without overwriting the width the user chose.
    private var effectiveWidth: CGFloat {
        limit.clamping(width, inContainerOfWidth: workspaceWidth)
    }

    var body: some View {
        if !isCollapsed {
            HStack(spacing: 0) {
                resizeHandle
                content()
                    .frame(width: effectiveWidth)
                    .clipped()
            }
        }
    }

    private var resizeHandle: some View {
        // The hit area *is* the view, 8pt wide, with the hairline drawn inside it. Putting
        // the grab area in an overlay that spills outside a 1pt frame looks identical and
        // cannot be hit — SwiftUI does not hit-test outside a view's own bounds.
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(AppThemeConstants.separatorColor)
                    .frame(width: 1)
            }
            .accessibilityLabel("Panel resize handle")
            .accessibilityHint("Drag left or right to resize the panel")
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            // Seeded from what is on screen, not from the stored width, so a
                            // drag in a shrunken window starts where the handle actually is.
                            dragStartWidth = effectiveWidth
                            dragStartX = value.startLocation.x
                        }
                        let delta = (dragStartX ?? value.startLocation.x) - value.location.x
                        let proposed = (dragStartWidth ?? width) + delta
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = limit.clamping(
                                proposed, inContainerOfWidth: workspaceWidth
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartX = nil
                    }
            )
    }
}
