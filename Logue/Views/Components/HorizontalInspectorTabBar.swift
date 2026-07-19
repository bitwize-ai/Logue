import SwiftUI

/// Xcode/Keynote-style horizontal icon tab bar for the inspector sidebar.
///
/// Two layout modes chosen automatically:
/// - **Flat** (≤8 tools): single icon row with group separators.
/// - **Grouped** (9+ tools): segmented group picker + icon row for the selected group.
struct HorizontalInspectorTabBar<Tool: ToolbarTool>: View {
    @Binding var activeTool: Tool?

    /// Tracks which group is selected in grouped layout.
    @State private var selectedGroup: String = Tool.groupOrder.first ?? ""

    private var useGroupedLayout: Bool {
        Tool.allCases.count > 8
    }

    private var groupedTools: [(group: String, tools: [Tool])] {
        Tool.groupOrder.compactMap { group in
            let tools = Tool.allCases.filter { $0.toolGroup == group }
            return tools.isEmpty ? nil : (group, Array(tools))
        }
    }

    private var toolsInSelectedGroup: [Tool] {
        Tool.allCases.filter { $0.toolGroup == selectedGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            if useGroupedLayout {
                groupPicker
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                iconRow(tools: Array(toolsInSelectedGroup))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                flatIconRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(AppThemeConstants.surfaceBackground)
        .onChange(of: activeTool) { _, newTool in
            if let tool = newTool, tool.toolGroup != selectedGroup {
                selectedGroup = tool.toolGroup
            }
        }
    }

    // MARK: - Group Picker (segmented control for 9+ tools)

    private var groupPicker: some View {
        HStack(spacing: 2) {
            ForEach(Tool.groupOrder, id: \.self) { group in
                Button {
                    withAnimation(.spring(duration: 0.2, bounce: 0.1)) {
                        selectedGroup = group
                        if let firstTool = Tool.allCases.first(where: { $0.toolGroup == group }) {
                            activeTool = firstTool
                        }
                    }
                } label: {
                    Text(group)
                        .font(.caption.weight(selectedGroup == group ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedGroup == group
                                ? AppThemeConstants.accent.opacity(AppThemeConstants.activeOpacity)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                        )
                        .foregroundStyle(selectedGroup == group ? AppThemeConstants.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group) tools")
                .accessibilityHint("Shows tools in the \(group) group")
                .accessibilityAddTraits(selectedGroup == group ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
        )
    }

    // MARK: - Flat Icon Row (for ≤8 tools)

    private var flatIconRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(groupedTools.enumerated()), id: \.element.group) { index, section in
                if index > 0 {
                    groupSeparator
                }
                ForEach(section.tools) { tool in
                    InspectorTabButton(
                        icon: tool.icon,
                        label: tool.rawValue,
                        isActive: activeTool == tool,
                        isEnabled: tool.isImplemented
                    ) {
                        withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                            activeTool = tool
                        }
                    }
                }
            }
        }
    }

    // MARK: - Icon Row (tools in a selected group)

    private func iconRow(tools: [Tool]) -> some View {
        HStack(spacing: 2) {
            ForEach(tools) { tool in
                InspectorTabButton(
                    icon: tool.icon,
                    label: tool.rawValue,
                    isActive: activeTool == tool,
                    isEnabled: tool.isImplemented
                ) {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        activeTool = tool
                    }
                }
            }
        }
    }

    private var groupSeparator: some View {
        Rectangle()
            .fill(AppThemeConstants.separatorColor)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
    }
}

// MARK: - InspectorTabButton

/// Individual icon button with accent underline indicator for the active state.
private struct InspectorTabButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(foregroundColor)

                // Accent underline indicator
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? AppThemeConstants.accent : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            // macOS HIG: minimum 22×22pt click target. Icons alone were ~11-16pt in AX,
            // below threshold and awkward to hit with pointer. The frame+contentShape
            // expand the actionable bounds without changing visual icon size.
            .frame(minHeight: 32)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityHint("Switches to the \(label) inspector panel")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(label)
        .disabled(!isEnabled)
    }

    private var foregroundColor: Color {
        if isActive {
            return AppThemeConstants.accent
        }
        return isEnabled ? Color.secondary : Color.secondary.opacity(0.5)
    }

    private var backgroundColor: Color {
        if isHovered, !isActive {
            return Color.primary.opacity(AppThemeConstants.hoverOpacity)
        }
        return .clear
    }
}
