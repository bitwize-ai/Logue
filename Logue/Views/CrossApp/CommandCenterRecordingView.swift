import SwiftUI

/// Top-centered recording island that blends with the macOS camera notch.
/// Compact pill with header controls and scrollable live transcript (~3 lines).
struct CommandCenterRecordingView: View {
    let recorder: RecordingSessionManager
    let activeMeetingID: UUID
    let onDismiss: () -> Void
    let onStop: () -> Void
    let onOpenInApp: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    private var segments: [TranscriptSegment] {
        MeetingStore.shared.meetings
            .first(where: { $0.id == activeMeetingID })?.segments ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header is always visible (sticky)
            headerRow

            // Transcript fills remaining space and scrolls
            transcriptArea
        }
        .frame(width: AppThemeConstants.recordingIslandWidth)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.recordingIslandCornerRadius, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.98)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.recordingIslandCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppThemeConstants.recordingIslandCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            ZStack {
                Circle()
                    .fill(AppThemeConstants.error.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                Circle()
                    .fill(AppThemeConstants.error)
                    .frame(width: 7, height: 7)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.6
                    pulseOpacity = 0.0
                }
            }

            if recorder.isRecording {
                Text(TranscriptSegment.formatTime(recorder.elapsedTime))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }

            AudioLevelMeter(level: recorder.audioLevel)
                .frame(width: 36, height: 10)

            if segments.isEmpty {
                Text("Listening\u{2026}")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            // Minimize — hides island without stopping recording
            Button {
                onDismiss()
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(.white.opacity(AppThemeConstants.hoverOpacity))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("Minimize")

            // Open in app
            Button {
                onOpenInApp()
            } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(.white.opacity(AppThemeConstants.hoverOpacity))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("Open in Logue")

            // Stop recording — collapses island + shows toast
            Button {
                Task { await recorder.stopRecording() }
                onStop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.caption2.weight(.bold))
                    Text("Stop")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(AppThemeConstants.error)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if segments.isEmpty {
                    Color.clear.frame(height: 1)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(segments.suffix(50), id: \.id) { segment in
                            transcriptRow(segment)
                                .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: segments.count) { _, _ in
                if let last = segments.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func transcriptRow(_ segment: TranscriptSegment) -> some View {
        Text(segment.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
    }
}

// MARK: - Recording Saved Toast

/// Brief floating toast shown after recording stops.
struct RecordingSavedToastView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppThemeConstants.success)
            Text("Meeting saved")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.96)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
