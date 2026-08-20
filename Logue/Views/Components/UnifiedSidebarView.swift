import SwiftUI

// MARK: - UnifiedSidebarView

/// A collapsible right sidebar used by both document and meeting workspaces.
///
/// Two states:
/// - **Collapsed** (0 px): fully hidden, maximum editor space.
/// - **Expanded** (tab bar + panel): horizontal inspector tabs at top, active tool's panel below.
struct UnifiedSidebarView<Tool: ToolbarTool, PanelContent: View>: View {
    @Binding var activeTool: Tool?
    @Binding var isCollapsed: Bool
    @Binding var panelWidths: [String: CGFloat]
    @ViewBuilder var panelContent: (Tool) -> PanelContent

    /// Set by the workspace this sidebar lives in — see `measuringWorkspaceWidth()`.
    @Environment(\.workspaceWidth) private var workspaceWidth

    /// Internal resize state
    @State private var currentWidth: CGFloat = 320

    private let defaultWidth: CGFloat = 320
    private let limit = SidebarWidthLimit.inspector

    /// The width actually rendered, clamped to what the window currently allows.
    ///
    /// Held separate from `currentWidth` so a *window resize* does not overwrite the width the
    /// user chose: shrinking narrows the panel on screen, and growing the window back returns
    /// it to the chosen width. A *drag* does overwrite it — `onChanged` stores the clamped
    /// value and `onEnded` persists it — which is intended, because a drag re-chooses the width
    /// from wherever the handle actually is.
    private var effectiveWidth: CGFloat {
        limit.clamping(currentWidth, inContainerOfWidth: workspaceWidth)
    }

    var body: some View {
        if !isCollapsed {
            HStack(spacing: 0) {
                resizeHandle

                VStack(spacing: 0) {
                    // Horizontal inspector tabs
                    HorizontalInspectorTabBar<Tool>(activeTool: $activeTool)

                    Divider()

                    // Panel content — all panels stay alive (opacity-hidden) so that
                    // AI streaming tasks and @State are preserved across tab switches.
                    ZStack {
                        ForEach(Array(Tool.allCases)) { tool in
                            panelContent(tool)
                                .frame(maxHeight: .infinity)
                                .opacity(activeTool == tool ? 1 : 0)
                                .allowsHitTesting(activeTool == tool)
                        }
                    }
                }
                .frame(width: effectiveWidth)
                .clipped()
            }
            .onAppear {
                if activeTool == nil, let firstTool = Tool.allCases.first {
                    activeTool = firstTool
                }
                // Restore user-resized width, or use default
                currentWidth = panelWidths["_shared"] ?? defaultWidth
            }
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        ResizableEdge(
            width: $currentWidth,
            clamp: { limit.clamping($0, inContainerOfWidth: workspaceWidth) },
            onScreenWidth: { effectiveWidth },
            onCommit: { panelWidths["_shared"] = $0 }
        )
    }
}
