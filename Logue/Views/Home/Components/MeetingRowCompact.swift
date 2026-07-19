import SwiftUI

struct MeetingRowCompact: View {
    let meeting: MeetingNote

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: meeting.recordingMode.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                    if meeting.duration > 0 {
                        Text("•")
                        Text(meeting.formattedDuration)
                            .font(.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if meeting.isPinned {
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
        .accessibilityLabel("Meeting: \(meeting.title)")
    }
}
