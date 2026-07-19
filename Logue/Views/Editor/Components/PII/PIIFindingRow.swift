import SwiftUI

struct PIIFindingRow: View {
    let finding: PIIFinding
    let risk: PIIRisk

    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.text)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Risk dot
            Circle()
                .fill(risk.color)
                .frame(width: 8, height: 8)
                .accessibilityLabel("\(risk.rawValue) risk")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                .fill(risk.color.opacity(AppThemeConstants.opacitySubtle))
        )
    }
}
