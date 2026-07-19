import SwiftUI

struct PIICategoryCard: View {
    let category: PIICategory
    let findings: [PIIFinding]

    @State private var isExpanded = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.subheadline)
                        .foregroundStyle(category.risk.color)
                        .frame(width: 24, height: 24)
                        .background(
                            category.risk.color.opacity(AppThemeConstants.activeOpacity),
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(category.examples)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(findings.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(category.risk.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(category.risk.color.opacity(AppThemeConstants.activeOpacity), in: Capsule())
                        .accessibilityLabel("\(findings.count) findings")

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Findings
            if isExpanded {
                Divider().padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(findings) { finding in
                        PIIFindingRow(finding: finding, risk: category.risk)
                    }
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(
                    category.risk.color.opacity(isHovered ? 0.35 : 0.15),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
