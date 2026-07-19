import SwiftUI

struct UpcomingEventCard: View {
    let event: CalendarEvent
    let onStartRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Time badge
            if event.isHappeningNow {
                StatusBadge(text: "Now", color: AppThemeConstants.error, showDot: true)
            } else if event.isStartingSoon {
                StatusBadge(text: "Soon", color: AppThemeConstants.warning, showDot: true)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Title
            Text(event.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)

            // Duration
            Text("\(event.durationMinutes) min")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            // Action buttons
            VStack(spacing: 4) {
                // Join meeting link (if URL available)
                // S-N5: Validate URL scheme before opening
                if let url = event.url, url.scheme == "https" || url.scheme == "http" {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.caption2)
                            Text("Join")
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppThemeConstants.success)
                    .controlSize(.mini)
                    .accessibilityLabel("Join meeting for \(event.title)")
                }

                // Start recording button
                Button {
                    onStartRecording()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .font(.caption2)
                        Text("Record")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.accent)
                .controlSize(.mini)
                .accessibilityLabel("Record meeting for \(event.title)")
            }
        }
        .padding(AppThemeConstants.paddingMedium)
        .frame(width: 140)
        .frame(minHeight: 130)
        .background(AppThemeConstants.surfaceBackground, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(
                    event.isHappeningNow ? AppThemeConstants.error.opacity(0.3) :
                        event.isStartingSoon ? AppThemeConstants.warning.opacity(0.3) :
                        Color.primary.opacity(AppThemeConstants.opacityLight),
                    lineWidth: 1
                )
        )
    }
}
