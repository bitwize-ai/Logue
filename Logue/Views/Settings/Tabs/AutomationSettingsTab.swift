import SwiftUI

/// Settings tab for managing scheduled AI automation tasks.
struct AutomationSettingsTab: View {
    @State private var taskManager = ScheduledTaskManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Automation")
                .font(.title3.bold())
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text("Schedule AI tasks to run automatically — digests, meeting prep, and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            PrivacyBadge("All automation runs on-device using your local AI model.")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(taskManager.tasks) { task in
                        TaskConfigurationCard(task: task)
                    }

                    // Run History
                    if !taskManager.runHistory.isEmpty {
                        TaskRunHistorySection()
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Task Configuration Card

private struct TaskConfigurationCard: View {
    let task: ScheduledTask
    @State private var taskManager = ScheduledTaskManager.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with toggle
            HStack(spacing: 12) {
                Image(systemName: task.taskType.icon)
                    .font(.title3)
                    .foregroundStyle(task.isEnabled ? AppThemeConstants.accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.taskType.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(task.taskType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { newValue in
                        taskManager.setEnabled(newValue, for: task.id)
                    }
                ))
                .toggleStyle(.switch)
                .tint(AppThemeConstants.accent)
                .labelsHidden()
                .accessibilityLabel("Enable \(task.taskType.displayName)")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(task.taskType.displayName) configuration")
            .accessibilityHint(isExpanded ? "Double-tap to collapse" : "Double-tap to expand")

            // Expanded configuration
            if isExpanded, task.isEnabled {
                Divider()
                    .padding(.top, 12)

                scheduleConfiguration
                    .padding(.top, 12)

                if task.taskType.supportsManualRun {
                    runNowButton
                        .padding(.top, 10)
                }

                if let lastRun = task.lastRunAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Last run: \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.chromeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(
                    task.isEnabled
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.borderOpacity)
                        : AppThemeConstants.borderColor,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Run Now

    private var runNowButton: some View {
        let isRunningThis = taskManager.isRunningTask && taskManager.currentTaskType == task.taskType
        return HStack(spacing: 8) {
            Button {
                Task { await taskManager.runTaskManually(taskID: task.id) }
            } label: {
                HStack(spacing: 4) {
                    if isRunningThis {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "play.fill").font(.caption2)
                    }
                    Text(isRunningThis ? "Running…" : "Run Now")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppThemeConstants.accent)
            .disabled(taskManager.isRunningTask)
            .accessibilityLabel("Run \(task.taskType.displayName) now")

            Spacer()
        }
    }

    // MARK: - Schedule Configuration

    @ViewBuilder
    private var scheduleConfiguration: some View {
        switch task.taskType {
        case .dailyDigest, .autoSummarize:
            dailyTimeConfig

        case .meetingPrep:
            meetingPrepConfig

        case .weeklyReview:
            weeklyConfig
        }
    }

    private var dailyTimeConfig: some View {
        HStack(spacing: 8) {
            Text("Run at")
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: timeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .frame(width: 90)

            Text("every day")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var meetingPrepConfig: some View {
        HStack(spacing: 8) {
            Text("Prepare")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: minutesBeforeBinding) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
            }
            .labelsHidden()
            .frame(width: 90)

            Text("before calendar events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklyConfig: some View {
        HStack(spacing: 8) {
            Text("Run on")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: dayOfWeekBinding) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
                Text("Tuesday").tag(3)
                Text("Wednesday").tag(4)
                Text("Thursday").tag(5)
                Text("Friday").tag(6)
                Text("Saturday").tag(7)
            }
            .labelsHidden()
            .frame(width: 120)

            Text("at")
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: timeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .frame(width: 90)
        }
    }

    // MARK: - Bindings

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = task.hour
                components.minute = task.minute
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newDate in
                var updated = task
                updated.hour = Calendar.current.component(.hour, from: newDate)
                updated.minute = Calendar.current.component(.minute, from: newDate)
                taskManager.updateTask(updated)
            }
        )
    }

    private var dayOfWeekBinding: Binding<Int> {
        Binding(
            get: { task.dayOfWeek ?? 2 },
            set: { newDay in
                var updated = task
                updated.dayOfWeek = newDay
                taskManager.updateTask(updated)
            }
        )
    }

    private var minutesBeforeBinding: Binding<Int> {
        Binding(
            get: { task.minutesBefore ?? 15 },
            set: { newMinutes in
                var updated = task
                updated.minutesBefore = newMinutes
                taskManager.updateTask(updated)
            }
        )
    }
}

// MARK: - Task Run History Section

private struct TaskRunHistorySection: View {
    @State private var taskManager = ScheduledTaskManager.shared
    @State private var selectedRecord: TaskRunRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Run History", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Clear") {
                    taskManager.clearHistory()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear run history")
            }

            ForEach(taskManager.runHistory.prefix(20)) { record in
                TaskRunRow(record: record)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRecord = record }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Double-tap to view details")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.chromeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(AppThemeConstants.borderColor, lineWidth: 1)
        )
        .sheet(item: $selectedRecord) { record in
            TaskRunDetailSheet(record: record)
        }
    }
}

// MARK: - Task Run Row

private struct TaskRunRow: View {
    let record: TaskRunRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            Image(systemName: record.taskType.icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.taskType.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(record.resultSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(record.runAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch record.status {
        case .success: "checkmark.circle.fill"
        case .noContent: "minus.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .success: AppThemeConstants.success
        case .noContent: AppThemeConstants.warning
        case .failed: AppThemeConstants.error
        }
    }
}

// MARK: - Task Run Detail Sheet

private struct TaskRunDetailSheet: View {
    let record: TaskRunRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    /// If the run produced a document, verify it still exists so we don't
    /// offer a broken "Open Document" button for a deleted file.
    private var documentIsAvailable: Bool {
        guard let id = record.createdDocumentID else { return false }
        return DocumentStore.shared.documents.contains { $0.id == id && !$0.isTrashed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: record.taskType.icon)
                    .font(.title3)
                    .foregroundStyle(AppThemeConstants.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.taskType.displayName)
                        .font(.headline)
                    Text(record.runAt.formatted(date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            Divider()

            // Result content
            ScrollView {
                Text(record.resultSummary)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            HStack {
                if documentIsAvailable, let docID = record.createdDocumentID {
                    Button {
                        DocumentStore.shared.selectedDocumentID = docID
                        dismiss()
                    } label: {
                        Label("Open Document", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Open generated document")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppThemeConstants.accent)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 480, minHeight: 250, idealHeight: 350)
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(AppThemeConstants.opacityMedium), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusLabel: String {
        switch record.status {
        case .success: "Success"
        case .noContent: "No Content"
        case .failed: "Failed"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .success: AppThemeConstants.success
        case .noContent: AppThemeConstants.warning
        case .failed: AppThemeConstants.error
        }
    }
}
