import SwiftUI

/// A single meeting card used in the grid view of MeetingListContentView.
struct MeetingGridCardView: View {
    let meeting: MeetingNote
    let store: MeetingStore
    let spaceStore: SpaceStore
    let onSelect: () -> Void
    let onRename: () -> Void

    var body: some View {
        let titleIsLong = meeting.title.count > 30
        let previewLines = titleIsLong ? 3 : 4

        HomeCardShell {
            onSelect()
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                header

                Text(meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let preview = previewText {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(previewLines)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        } contextMenu: {
            MeetingContextMenuContent(
                meeting: meeting,
                store: store,
                spaceStore: spaceStore,
                onRename: onRename
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: meeting.recordingMode.iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                if meeting.duration > 0 {
                    Text(meeting.formattedDuration)
                        .monospacedDigit()
                }
                if !meeting.actionItems.isEmpty {
                    let pending = meeting.actionItems.filter { !$0.isCompleted }.count
                    if pending > 0 {
                        if meeting.duration > 0 {
                            Text("\u{00B7}")
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "checklist")
                            Text("\(pending)")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(AppThemeConstants.actionBadgeColor)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Preview Text

    private var previewText: String? {
        if let summary = meeting.summary {
            return summary
        }
        if !meeting.segments.isEmpty {
            return meeting.segments.prefix(8).map(\.text).joined(separator: " ")
        }
        return nil
    }
}
