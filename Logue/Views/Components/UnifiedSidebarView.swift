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

    // Internal resize state
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?
    @State private var currentWidth: CGFloat = 320

    private let defaultWidth: CGFloat = 320
    private let minWidth: CGFloat = 260
    private let maxWidth: CGFloat = 520

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
                .frame(width: currentWidth)
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
        Rectangle()
            .fill(AppThemeConstants.separatorColor)
            .frame(width: 1)
            .accessibilityLabel("Sidebar resize handle")
            .accessibilityHint("Drag left or right to resize the sidebar panel")
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
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
                                    dragStartWidth = currentWidth
                                    dragStartX = value.startLocation.x
                                }
                                let delta = (dragStartX ?? value.startLocation.x) - value.location.x
                                let proposed = (dragStartWidth ?? currentWidth) + delta
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    currentWidth = min(max(proposed, minWidth), maxWidth)
                                }
                            }
                            .onEnded { _ in
                                // Persist shared width
                                panelWidths["_shared"] = currentWidth
                                dragStartWidth = nil
                                dragStartX = nil
                            }
                    )
            )
    }
}
