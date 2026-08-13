import SwiftUI

/// A library surface with an on-demand right panel.
///
/// Wraps the existing list view rather than modifying it: `DocumentListContentView` and
/// `MeetingListContentView` are shared with the space surfaces, and a panel of *all* action
/// items has no business appearing inside one space.
///
/// The panel machinery is `UnifiedSidebarView`, the same component the document and meeting
/// workspaces use, so resize, remembered width and collapse behave identically here.
struct LibrarySurfaceView<Tool: ToolbarTool, Content: View, Panel: View>: View {
    @Binding var isPanelCollapsed: Bool
    /// Shown on the toggle button. This is the signal that used to be a sidebar badge, so
    /// it is the one thing the move must not lose.
    var badgeCount: Int?
    let toggleHelp: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let panel: (Tool) -> Panel

    @State private var activeTool: Tool?
    @State private var panelWidths: [String: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            UnifiedSidebarView(
                activeTool: $activeTool,
                isCollapsed: $isPanelCollapsed,
                panelWidths: $panelWidths,
                panelContent: panel
            )
        }
        .measuringWorkspaceWidth()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                toggleButton
            }
        }
    }

    private var toggleButton: some View {
        Button {
            isPanelCollapsed.toggle()
        } label: {
            Image(systemName: Tool.allCases.first?.icon ?? "sidebar.right")
                .overlay(alignment: .topTrailing) {
                    if let badgeCount, badgeCount > 0 {
                        badge(badgeCount)
                    }
                }
        }
        .help(toggleHelp)
        .accessibilityLabel(accessibilityLabel)
    }

    private func badge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(AppThemeConstants.accent, in: Capsule())
            // Pushed clear of the glyph so it reads as a badge rather than part of the icon.
            .offset(x: 7, y: -6)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let name = Tool.allCases.first?.rawValue ?? "Panel"
        guard let badgeCount, badgeCount > 0 else { return name }
        return "\(name), \(badgeCount) waiting"
    }
}
