import SwiftUI

/// Combined "Needs Attention" card — overdue/due-today action items + upcoming calendar events.
/// Hides entirely when there's nothing to show.
struct HomeAttentionCard: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(CalendarManager.self) private var calendarManager
    let onStartMeeting: (CalendarEvent) -> Void

    var body: some View {
        let urgentItems = urgentActionItems
        let events = Array(calendarManager.upcomingEvents.prefix(3))

        if !urgentItems.isEmpty || !events.isEmpty {
            InsightCardShell {
                VStack(alignment: .leading, spacing: 14) {
                    CardSectionHeader(
                        icon: "exclamationmark.triangle.fill",
                        title: "Needs Attention",
                        color: urgentItems.contains(where: \.isOverdue)
                            ? AppThemeConstants.error : AppThemeConstants.warning
                    )

                    if !urgentItems.isEmpty {
                        actionItemsSection(urgentItems)
                    }

                    if !urgentItems.isEmpty, !events.isEmpty {
                        Divider()
                    }

                    if !events.isEmpty {
                        upcomingEventsSection(events)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Action Items Section

    private func actionItemsSection(_ items: [UrgentActionItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                actionItemRow(item)
                if item.id != items.last?.id {
                    Divider().padding(.leading, 28)
                }
            }
        }
    }

    private func actionItemRow(_ item: UrgentActionItem) -> some View {
        HStack(spacing: 8) {
            Button {
                meetingStore.toggleActionItemCompleted(
                    itemID: item.actionItem.id,
                    in: item.meetingID
                )
            } label: {
                Image(systemName: item.actionItem.isCompleted
                    ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(item.actionItem.isCompleted
                        ? AppThemeConstants.success : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.actionItem.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.actionItem.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(item.actionItem.isCompleted)

                HStack(spacing: 6) {
                    if let assignee = item.actionItem.assignee, !assignee.isEmpty {
                        Text(assignee)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        meetingStore.selectedMeetingID = item.meetingID
                    } label: {
                        Text(item.meetingTitle)
                            .font(.caption)
                            .foregroundStyle(AppThemeConstants.accent)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if let dueDate = item.actionItem.dueDate {
                dueBadge(dueDate, isOverdue: item.isOverdue)
            }
        }
        .padding(.vertical, 4)
    }

    private func dueBadge(_ date: Date, isOverdue: Bool) -> some View {
        let color = isOverdue ? AppThemeConstants.error : AppThemeConstants.warning
        return Text(date.formatted(.relative(presentation: .named)))
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(AppThemeConstants.opacityLight), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Upcoming Events Section

    private func upcomingEventsSection(_ events: [CalendarEvent]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                upcomingEventRow(event)
                if index < events.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func upcomingEventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 10) {
            Group {
                if event.isHappeningNow {
                    Text("NOW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppThemeConstants.error)
                } else {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(event.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // S-N5: Validate URL scheme before opening calendar event URLs
            if let url = event.url, url.scheme == "https" || url.scheme == "http" {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundStyle(AppThemeConstants.success)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join meeting")
            }

            Button { onStartMeeting(event) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "record.circle")
                        .font(.caption)
                    Text("Record")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .tint(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.accent)
            .controlSize(.mini)
        }
    }

    // MARK: - Data

    private var urgentActionItems: [UrgentActionItem] {
        let now = Date()
        let endOfToday = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        )

        var result: [UrgentActionItem] = []
        for meeting in meetingStore.activeMeetings where !meeting.isArchived {
            for item in meeting.actionItems where !item.isCompleted {
                guard let dueDate = item.dueDate, dueDate < endOfToday else { continue }
                let isOverdue = dueDate < now
                result.append(UrgentActionItem(
                    actionItem: item,
                    meetingID: meeting.id,
                    meetingTitle: meeting.title,
                    isOverdue: isOverdue
                ))
            }
        }
        return result
            .sorted { ($0.isOverdue ? 0 : 1, $0.actionItem.dueDate ?? .distantFuture)
                < ($1.isOverdue ? 0 : 1, $1.actionItem.dueDate ?? .distantFuture)
            }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Urgent Action Item

private struct UrgentActionItem: Identifiable {
    let actionItem: ActionItem
    let meetingID: UUID
    let meetingTitle: String
    let isOverdue: Bool

    var id: UUID {
        actionItem.id
    }
}
