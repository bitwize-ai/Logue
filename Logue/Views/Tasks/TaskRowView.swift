import SwiftUI

/// One task in the list.
struct TaskRowView: View {
    let task: TaskItem
    let meetingTitle: String?
    let onToggle: () -> Void
    let onOpenSource: () -> Void

    private var isDone: Bool {
        task.status == .done
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)

                if !badges.isEmpty || meetingTitle != nil {
                    detailRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var detailRow: some View {
        HStack(spacing: 6) {
            ForEach(badges, id: \.label) { badge in
                Label(badge.label, systemImage: badge.symbol)
                    .foregroundStyle(badge.tint)
            }
            if let meetingTitle {
                Button(action: onOpenSource) {
                    Label(meetingTitle, systemImage: "waveform")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open the meeting this came from")
            }
        }
        .font(.caption)
    }

    private struct Badge {
        let label: String
        let symbol: String
        let tint: Color
    }

    private var badges: [Badge] {
        var result: [Badge] = []
        if let due = task.dueDate {
            result.append(Badge(
                label: due.formatted(date: .abbreviated, time: .omitted),
                symbol: "calendar",
                tint: task.isOverdue ? .red : .secondary
            ))
        }
        if task.priority != .medium {
            result.append(Badge(
                label: task.priority.displayName,
                symbol: task.priority.symbolName,
                tint: task.priority == .high ? .orange : .secondary
            ))
        }
        if let recurrence = task.recurrence {
            result.append(Badge(label: recurrence.displayName, symbol: "repeat", tint: .secondary))
        }
        for tag in task.tags {
            result.append(Badge(label: tag, symbol: "number", tint: .secondary))
        }
        return result
    }
}
