import SwiftUI

/// Floating popup for the `/` slash command — shows filterable block types.
struct SlashCommandView: View {
    let filterText: String
    let onSelect: (BlockType) -> Void
    let onDismiss: () -> Void

    private var filteredTypes: [BlockType] {
        guard !filterText.isEmpty else { return BlockType.allCases }
        let lowered = filterText.lowercased()
        return BlockType.allCases.filter {
            $0.displayName.lowercased().contains(lowered)
                || $0.rawValue.lowercased().contains(lowered)
                || $0.description.lowercased().contains(lowered)
        }
    }

    /// Filtered types grouped by category. When filtering, flat list; otherwise grouped.
    private var groupedFiltered: [(title: String, types: [BlockType])] {
        if !filterText.isEmpty {
            let types = filteredTypes
            return types.isEmpty ? [] : [("Results", types)]
        }
        return BlockType.groupedByCategory.compactMap { group in
            let types = group.types.filter { filteredTypes.contains($0) }
            return types.isEmpty ? nil : (group.category.rawValue, types)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Blocks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !filterText.isEmpty {
                    Text("Filtering: \(filterText)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if groupedFiltered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No matching blocks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groupedFiltered, id: \.title) { group in
                            Text(group.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                                .padding(.bottom, 2)

                            ForEach(group.types, id: \.rawValue) { blockType in
                                SlashCommandRow(blockType: blockType) {
                                    onSelect(blockType)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 240, height: 320)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(AppThemeConstants.panelShadowOpacity),
            radius: AppThemeConstants.panelShadowRadius,
            x: 0,
            y: AppThemeConstants.panelShadowY
        )
    }
}

// MARK: - Row

private struct SlashCommandRow: View {
    let blockType: BlockType
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: blockType.iconName)
                    .font(.system(size: AppThemeConstants.menuIconPointSize, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                            .fill(Color.primary.opacity(isHovered ? AppThemeConstants.opacityLight : AppThemeConstants.opacitySubtle))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(blockType.displayName)
                        .font(.system(size: AppThemeConstants.menuIconPointSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(blockType.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(AppThemeConstants.opacityLight) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
