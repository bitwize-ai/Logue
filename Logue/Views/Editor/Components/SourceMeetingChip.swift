import SwiftUI

/// Small chip shown above the editor when the document was auto-created from a meeting.
/// Tapping invokes `onTap` so the host can navigate to the source meeting, letting users
/// trace notes back to their recording.
struct SourceMeetingChip: View {
    let meeting: MeetingNote
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.accent)

                Text("From meeting:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(meeting.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppThemeConstants.accent)
                    .lineLimit(1)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(meeting.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityLabel("Open source meeting: \(meeting.title)")
        .help("Open source meeting")
    }
}
