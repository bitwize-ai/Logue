import AppKit
import SwiftUI

/// A draggable edge that resizes the panel beside it.
///
/// One copy, used by every resizable side panel. The drag machinery was duplicated verbatim
/// between the workspace inspector and the library panels — same delta maths, same transaction,
/// same cursor push and pop — which is how the hit-target fix below ended up living in one of
/// them and not the other.
///
/// The hit area *is* the view, 8pt wide, with the hairline drawn inside it. Putting the grab
/// area in an `.overlay` that spills outside a 1pt frame looks identical and cannot be hit:
/// SwiftUI does not hit-test outside a view's own bounds.
///
/// That costs layout, and deliberately. The workspace inspector's handle used to be a 1pt
/// rectangle with the grab area overlaid, so it occupied 1pt beside the panel; this occupies
/// 8pt, and the editor is 7pt narrower whenever an inspector is open. The alternative is a
/// handle that looks draggable and is not, which is the defect this type exists to fix. Kept
/// as one type so the two surfaces cannot drift back apart.
struct ResizableEdge: View {
    /// The width being edited, in points.
    @Binding var width: CGFloat
    /// Clamps the result to what the window can currently spare.
    let clamp: (CGFloat) -> CGFloat
    /// What is on screen right now, which a drag starts from — not the stored width, so a
    /// drag in a shrunken window starts where the handle actually is.
    let onScreenWidth: () -> CGFloat
    /// Called once the drag ends, for panels that persist the chosen width.
    var onCommit: (CGFloat) -> Void = { _ in }

    private static let hitWidth: CGFloat = 8

    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.hitWidth)
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
                            dragStartWidth = onScreenWidth()
                            dragStartX = value.startLocation.x
                        }
                        let delta = (dragStartX ?? value.startLocation.x) - value.location.x
                        let proposed = (dragStartWidth ?? width) + delta
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = clamp(proposed)
                        }
                    }
                    .onEnded { _ in
                        onCommit(width)
                        dragStartWidth = nil
                        dragStartX = nil
                    }
            )
    }
}
