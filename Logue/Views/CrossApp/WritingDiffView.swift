import SwiftUI

/// Visual diff rendering between original and improved text.
struct WritingDiffView: View {
    let original: String
    let improved: String

    @State private var viewMode: DiffViewMode = .inline

    enum DiffViewMode: String, CaseIterable {
        case inline = "Inline"
        case sideBySide = "Side by Side"
        case improved = "Result Only"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(DiffViewMode.allCases, id: \.rawValue) { mode in
                    Button(action: { viewMode = mode }, label: {
                        Text(mode.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(viewMode == mode ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                                    .fill(viewMode == mode ? AppThemeConstants.brandPrimary.opacity(AppThemeConstants.opacityStrong) : Color.clear)
                            )
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.rawValue)
                    .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
                }
                Spacer()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Diff view mode")

            ScrollView {
                switch viewMode {
                case .inline: inlineDiffView
                case .sideBySide: sideBySideView
                case .improved: improvedOnlyView
                }
            }
            .frame(maxHeight: 250)
        }
    }

    // MARK: - Inline

    private var inlineDiffView: some View {
        let diff = TextDiff.compute(original: original, improved: improved)
        return FlowLayout(spacing: 3) {
            ForEach(diff.changes) { change in
                Text(change.text)
                    .font(.caption)
                    .foregroundStyle(colorForChange(change.type))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                            .fill(backgroundForChange(change.type))
                    )
                    .strikethrough(change.type == .removed, color: AppThemeConstants.error.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(Color.primary.opacity(AppThemeConstants.opacitySubtle))
                .overlay(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                        .stroke(Color.primary.opacity(AppThemeConstants.opacitySubtle + 0.02), lineWidth: 1)
                )
        )
    }

    // MARK: - Side by Side

    private var sideBySideView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(AppThemeConstants.error.opacity(0.6)).frame(width: 6, height: 6)
                    Text("Original")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppThemeConstants.error.opacity(0.8))
                }
                Text(original)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                    .fill(AppThemeConstants.error.opacity(AppThemeConstants.opacitySubtle))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                            .stroke(AppThemeConstants.error.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
                    )
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(AppThemeConstants.success.opacity(0.6)).frame(width: 6, height: 6)
                    Text("Improved")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppThemeConstants.success.opacity(0.8))
                }
                Text(improved)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                    .fill(AppThemeConstants.success.opacity(AppThemeConstants.opacitySubtle))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                            .stroke(AppThemeConstants.success.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Result Only

    private var improvedOnlyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppThemeConstants.success)
                Text("Improved Text")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppThemeConstants.success.opacity(0.8))
            }
            Text(improved)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.success.opacity(AppThemeConstants.opacitySubtle))
                .overlay(
                    RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                        .stroke(AppThemeConstants.success.opacity(AppThemeConstants.opacityLight), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func colorForChange(_ type: DiffChangeType) -> Color {
        switch type {
        case .unchanged: .primary
        case .added: AppThemeConstants.success
        case .removed: AppThemeConstants.error
        }
    }

    private func backgroundForChange(_ type: DiffChangeType) -> Color {
        switch type {
        case .unchanged: .clear
        case .added: AppThemeConstants.success.opacity(AppThemeConstants.opacityLight)
        case .removed: AppThemeConstants.error.opacity(AppThemeConstants.opacityLight)
        }
    }
}
