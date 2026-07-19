import SwiftUI

struct DocumentRowCompact: View {
    let document: WritingDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(document.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if document.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(AppThemeConstants.pinnedColor)
                    .accessibilityLabel("Favorited")
            }
        }
        .padding(AppThemeConstants.paddingMedium)
        .background(AppThemeConstants.surfaceBackground, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
                .stroke(AppThemeConstants.borderColor, lineWidth: 1)
        )
        .overlay(HandCursorArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Document: \(document.title)")
    }
}
