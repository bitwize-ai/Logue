import SwiftUI

/// A single meeting row used in the list view of MeetingListContentView.
struct MeetingListRowView: View {
    let meeting: MeetingNote
    let store: MeetingStore
    let spaceStore: SpaceStore
    let onSelect: () -> Void
    let onRename: () -> Void

    var body: some View {
        HomeCardShell(
            action: onSelect,
            accessibilityLabel: meetingAccessibilityLabel,
            accessibilityHint: "Opens meeting"
        ) { _ in
            HStack(spacing: 12) {
                Image(systemName: meeting.recordingMode.iconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    titleRow
                    metadataRow
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    actionBadge

                    Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        } contextMenu: {
            MeetingContextMenuContent(
                meeting: meeting,
                store: store,
                spaceStore: spaceStore,
                onRename: onRename
            )
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack {
            Text(meeting.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            if meeting.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(AppThemeConstants.pinnedColor)
                    .accessibilityLabel("Pinned")
            }
            if meeting.isArchived {
                Image(systemName: "archivebox")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Archived")
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if meeting.duration > 0 {
                Text(meeting.formattedDuration)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Action Badge

    @ViewBuilder
    private var actionBadge: some View {
        if !meeting.actionItems.isEmpty {
            let pending = meeting.actionItems.filter { !$0.isCompleted }.count
            if pending > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checklist")
                        .font(.caption2)
                    Text("\(pending)")
                        .font(.caption2.bold())
                }
                .foregroundStyle(AppThemeConstants.actionBadgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    AppThemeConstants.actionBadgeColor.opacity(AppThemeConstants.opacityLight),
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(pending) pending action items")
            }
        }
    }

    /// Single-string accessibility label for the row card. VoiceOver reads this in full on focus.
    private var meetingAccessibilityLabel: String {
        var parts: [String] = [meeting.title]
        if meeting.isPinned {
            parts.append("pinned")
        }
        if meeting.isArchived {
            parts.append("archived")
        }
        let pending = meeting.actionItems.filter { !$0.isCompleted }.count
        if pending > 0 {
            parts.append("\(pending) pending action item\(pending == 1 ? "" : "s")")
        }
        parts.append(meeting.createdAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }
}

// MARK: - Context Menu

/// Reusable context menu content for a meeting item (shared by list and grid).
struct MeetingContextMenuContent: View {
    let meeting: MeetingNote
    let store: MeetingStore
    let spaceStore: SpaceStore
    let onRename: () -> Void

    var body: some View {
        Button {
            store.selectedMeetingID = meeting.id
        } label: {
            Label("Open", systemImage: "waveform")
        }
        Button {
            store.togglePin(id: meeting.id)
        } label: {
            Label(
                meeting.isPinned ? "Unpin" : "Pin",
                systemImage: meeting.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            onRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            store.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        if !spaceStore.topLevelSpaces.isEmpty || meeting.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: meeting.spaceID) { newSpaceID in
                    store.moveMeeting(id: meeting.id, toSpace: newSpaceID)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            store.trashMeeting(id: meeting.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}
