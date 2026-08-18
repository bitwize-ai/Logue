import SwiftUI

/// One extracted action item awaiting a decision.
///
/// The row offers the two decisions an inbox is for — this is work, or this is not — rather
/// than a completion checkbox. Completing an item in place is still reachable from the
/// context menu; it is just no longer the gesture the row invites.
struct ActionItemInboxRow: View {
    let item: DashboardActionItem
    @Environment(MeetingStore.self) private var meetingStore
    @State private var taskStore = TaskStore.shared
    @State private var isHovered = false

    /// Promote and dismiss, revealed on hover.
    ///
    /// Both are shown only on hover for the same reason the promote button already was: one
    /// permanently-visible control per row competes with the due badge for the eye.
    @ViewBuilder
    private var decisionControls: some View {
        if taskStore.promotedTask(for: item.actionItem.id) != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Already on your task list")
                .accessibilityLabel("Already in Tasks")
        } else if item.actionItem.isDismissed {
            Button {
                meetingStore.setActionItemDismissed(
                    false, itemID: item.actionItem.id, in: item.meetingID
                )
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Put this back in the inbox")
            .accessibilityLabel("Restore to inbox")
            .opacity(isHovered ? 1 : 0)
        } else {
            HStack(spacing: 6) {
                Button {
                    taskStore.promote(item.actionItem, from: item.meetingID)
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add this to your tasks")
                .accessibilityLabel("Add to Tasks")

                Button {
                    meetingStore.setActionItemDismissed(
                        true, itemID: item.actionItem.id, in: item.meetingID
                    )
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Not something to act on")
                .accessibilityLabel("Dismiss")
            }
            .opacity(isHovered ? 1 : 0)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.actionItem.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(item.actionItem.isCompleted ? .secondary : .primary)
                    .strikethrough(item.actionItem.isCompleted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    meetingLink

                    if let assignee = item.actionItem.assignee, !assignee.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 3) {
                            Image(systemName: "person")
                                .font(.caption2)
                            Text(assignee)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            decisionControls

            if let dueDate = item.actionItem.dueDate {
                dueBadge(dueDate)
            } else if !item.actionItem.isCompleted {
                Text("No due date")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            // Accent wash rather than `surfaceBackground`: this row lives on a panel, which
            // is already that colour, so the old hover was invisible here.
            isHovered
                ? AppThemeConstants.accent.opacity(AppThemeConstants.hoverOpacity)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            openMeeting()
        }
        .contextMenu {
            contextMenuContent
        }
        // Accessibility: `.combine` was flattening + stripping the explicit label in macOS 26
        // SwiftUI. `.contain` keeps inner buttons individually reachable (promote, dismiss,
        // meeting link); the explicit label + isButton trait + primary action expose the row
        // itself as a named, activatable AXButton.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            openMeeting()
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            openMeeting()
        } label: {
            Label("Open Meeting", systemImage: "arrow.up.right.square")
        }
        Button {
            HapticFeedback.levelChange()
            meetingStore.toggleActionItemCompleted(
                itemID: item.actionItem.id,
                in: item.meetingID
            )
        } label: {
            Label(
                item.actionItem.isCompleted ? "Mark Incomplete" : "Mark Complete",
                systemImage: item.actionItem.isCompleted ? "circle" : "checkmark.circle"
            )
        }
        Button {
            meetingStore.setActionItemDismissed(
                !item.actionItem.isDismissed, itemID: item.actionItem.id, in: item.meetingID
            )
        } label: {
            Label(
                item.actionItem.isDismissed ? "Restore to Inbox" : "Dismiss",
                systemImage: item.actionItem.isDismissed ? "arrow.uturn.backward" : "xmark.circle"
            )
        }
    }

    private var meetingLink: some View {
        Button {
            openMeeting()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                    .font(.caption2)
                Text(item.meetingTitle)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(AppThemeConstants.accent)
        }
        .buttonStyle(.plain)
    }

    private func dueBadge(_ date: Date) -> some View {
        let color = item.urgency.color
        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text(date.formatted(.relative(presentation: .named)))
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            color.opacity(AppThemeConstants.opacityLight),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func openMeeting() {
        meetingStore.selectedMeetingID = item.meetingID
    }

    private var accessibilityText: String {
        var parts: [String] = [item.actionItem.title]
        if item.actionItem.isCompleted {
            parts.append("completed")
        }
        if item.actionItem.isDismissed {
            parts.append("dismissed")
        }
        parts.append("from \(item.meetingTitle)")
        if let due = item.actionItem.dueDate {
            parts.append("due \(due.formatted(.relative(presentation: .named)))")
        }
        if let assignee = item.actionItem.assignee, !assignee.isEmpty {
            parts.append("assigned to \(assignee)")
        }
        return parts.joined(separator: ", ")
    }
}
