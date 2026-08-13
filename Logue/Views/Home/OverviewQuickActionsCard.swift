import SwiftUI

/// Compact inline quick action buttons for the Home page.
struct HomeQuickActions: View {
    let onStartRecording: () -> Void
    let onNewMeeting: () -> Void
    let onNewDocument: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HomeQuickActionButton(
                icon: "mic.badge.plus",
                title: "Voice Note",
                color: AppThemeConstants.accent,
                action: onStartRecording
            )
            HomeQuickActionButton(
                icon: "waveform",
                title: "New Meeting",
                color: AppThemeConstants.success,
                action: onNewMeeting
            )
            HomeQuickActionButton(
                icon: "doc.badge.plus",
                title: "New Document",
                color: AppThemeConstants.categoryPurple,
                action: onNewDocument
            )
        }
    }
}

/// One quick-action tile.
///
/// Lifted out of `HomeQuickActions` so the first-run starter card can use the same tile
/// with its own wording. The alternative was reusing `HomeQuickActions` wholesale and
/// living with labels that describe the wrong action — a button that says "New Meeting"
/// while creating a document is worse than a little duplication.
struct HomeQuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppThemeConstants.paddingMedium)
            .background(
                color.opacity(AppThemeConstants.opacityLight),
                in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusMedium)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(HandCursorArea())
        .accessibilityLabel(title)
    }
}

/// Sticky recording banner shown at the top of the Home page during active recording.
struct HomeRecordingBanner: View {
    let recorder: RecordingSessionManager
    let onStopRecording: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppThemeConstants.error)
                .frame(width: 8, height: 8)

            Text("Recording...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppThemeConstants.error)

            AudioLevelMeter(level: recorder.audioLevel)
                .frame(height: 16)
                .frame(maxWidth: 120)

            Text(DurationFormatter.minutesSeconds(recorder.elapsedTime))
                .font(.caption.monospacedDigit().weight(.medium))

            Spacer()

            Button { onStopRecording() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill").font(.caption2)
                    Text("Stop").font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppThemeConstants.error)
            .controlSize(.mini)
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppThemeConstants.surfaceBackground)
    }
}
