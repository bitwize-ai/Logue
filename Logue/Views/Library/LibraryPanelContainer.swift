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
        ResizableEdge(
            width: $width,
            clamp: { limit.clamping($0, inContainerOfWidth: workspaceWidth) },
            onScreenWidth: { effectiveWidth }
        )
    }
}
