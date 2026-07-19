import SwiftUI

/// Card for a recorded meeting, shown in the meetings grid.
struct MeetingCardView: View {
    @Environment(MeetingStore.self) private var store
    let meeting: MeetingNote

    @State private var showMenu = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HomeCardShell(
            action: { store.selectedMeetingID = meeting.id },
            content: { isHovered in cardBody(isHovered: isHovered) },
            contextMenu: { contextMenuItems }
        )
        .alert("Delete Meeting?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                store.trashMeeting(id: meeting.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(meeting.title)\" will be permanently deleted.")
        }
    }

    // MARK: - Computed Helpers

    private var statusColor: Color {
        if meeting.summary != nil {
            return AppThemeConstants.success
        }
        if !meeting.segments.isEmpty {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.categoryGray
    }

    private var statusAccessibilityLabel: String {
        if meeting.summary != nil {
            return "Summarized"
        }
        if !meeting.segments.isEmpty {
            return "Transcribed"
        }
        return "No transcript"
    }

    private var completedActionCount: Int {
        meeting.actionItems.filter(\.isCompleted).count
    }

    private var previewText: String? {
        if let summary = meeting.summary {
            return summary
        }
        if !meeting.segments.isEmpty {
            return meeting.segments.prefix(8).map(\.text).joined(separator: " ")
        }
        return nil
    }

    // MARK: - Card Body

    private func cardBody(isHovered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            previewArea
            Divider()
            footerArea(isHovered: isHovered)
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack(alignment: .topLeading) {
            AppThemeConstants.chromeBackground
                .frame(maxWidth: .infinity)
                .frame(height: 110)

            VStack(alignment: .leading, spacing: 6) {
                // Header: status dot + mode + duration pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(statusAccessibilityLabel)

                    Image(systemName: meeting.recordingMode.iconName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(meeting.recordingMode.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if meeting.duration > 0 {
                        Text(meeting.formattedDuration)
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.primary.opacity(AppThemeConstants.opacitySubtle),
                                in: Capsule()
                            )
                            .foregroundStyle(.secondary)
                    }
                }

                // Body: summary → transcript → placeholder
                if let text = previewText {
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            AppThemeConstants.mutedText
                        )
                        .lineLimit(5)
                } else {
                    HStack {
                        Spacer()
                        Image(
                            systemName: meeting.recordingMode.isVoiceNote
                                ? "waveform" : "text.bubble"
                        )
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(AppThemeConstants.paddingSmall)
        }
    }

    // MARK: - Footer Area

    private func footerArea(isHovered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow(isHovered: isHovered)
            metadataRow
        }
        .padding(.horizontal, AppThemeConstants.paddingSmall)
        .padding(.vertical, AppThemeConstants.paddingSmall)
    }

    private func titleRow(isHovered: Bool) -> some View {
        HStack(spacing: 6) {
            Image(
                systemName: meeting.recordingMode.isVoiceNote
                    ? "mic.badge.plus" : "waveform"
            )
            .font(.caption2)
            .foregroundColor(AppThemeConstants.accent)

            Text(meeting.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .help(meeting.title)

            Spacer()

            if meeting.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundColor(AppThemeConstants.pinnedColor)
            }
            if isHovered {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .padding(4)
                        .background(
                            .quaternary,
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                        )
                }
                .buttonStyle(.plain)
                .overlay(HandCursorArea())
                .help("Meeting options")
                .accessibilityLabel("Meeting options")
                .popover(
                    isPresented: $showMenu,
                    arrowEdge: .bottom
                ) {
                    cardMenuContent
                }
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(
                meeting.createdAt.formatted(
                    .relative(presentation: .named)
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if !meeting.actionItems.isEmpty {
                let allDone = completedActionCount
                    == meeting.actionItems.count
                HStack(spacing: 2) {
                    Image(
                        systemName: allDone
                            ? "checkmark.circle.fill"
                            : "circle.dotted.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(allDone ? AppThemeConstants.success : .secondary)
                    Text(
                        "\(completedActionCount)/\(meeting.actionItems.count)"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            if !meeting.bookmarks.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(AppThemeConstants.warning)
                    Text("\(meeting.bookmarks.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if meeting.template != .general {
                Text(meeting.template.label)
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight),
                        in: Capsule()
                    )
                    .foregroundStyle(AppThemeConstants.accent)
            }
        }
    }

    // MARK: - Popover Menu

    private var cardMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                store.togglePin(id: meeting.id)
                showMenu = false
            } label: {
                Label(
                    meeting.isPinned
                        ? "Unpin"
                        : "Pin",
                    systemImage: meeting.isPinned
                        ? "pin.slash" : "pin"
                )
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                store.toggleArchive(id: meeting.id)
                showMenu = false
            } label: {
                Label(
                    meeting.isArchived ? "Unarchive" : "Archive",
                    systemImage: meeting.isArchived
                        ? "tray.and.arrow.up" : "archivebox"
                )
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button(role: .destructive) {
                showMenu = false
                showDeleteConfirmation = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(AppThemeConstants.error)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 6)
        .frame(minWidth: 180)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            store.selectedMeetingID = meeting.id
        } label: {
            Label("Open", systemImage: "waveform")
        }
        Button {
            store.togglePin(id: meeting.id)
        } label: {
            Label(
                meeting.isPinned
                    ? "Unpin"
                    : "Pin",
                systemImage: meeting.isPinned
                    ? "pin.slash" : "pin"
            )
        }
        Button {
            store.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived
                    ? "tray.and.arrow.up" : "archivebox"
            )
        }
        Divider()
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}
