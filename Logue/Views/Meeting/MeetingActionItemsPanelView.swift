import SwiftUI

/// Right panel showing action items extracted from the meeting.
struct MeetingActionItemsPanelView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(RecordingSessionManager.self) private var recorder
    let meeting: MeetingNote
    @State private var extractionMessage: String?

    private var isExtracting: Bool {
        store.generatingMeetingIDs.contains(meeting.id)
    }

    private var hasSummary: Bool {
        meeting.smartMinutes != nil || meeting.summary != nil
    }

    private var isLiveRecording: Bool {
        recorder.isRecording && recorder.currentMeetingID == meeting.id
    }

    var body: some View {
        Group {
            if isExtracting, meeting.actionItems.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(0.9)
                    VStack(spacing: 4) {
                        Text("Extracting action items...")
                            .font(.callout.weight(.medium))
                        Text("Using on-device AI to identify tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if meeting.actionItems.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: extractionMessage != nil ? "No action items found" : "No action items",
                    description: extractionMessage
                        ?? (meeting.segments.isEmpty
                            ? "Start a meeting to extract action items."
                            : (hasSummary
                                ? "Tap to extract action items from the existing summary."
                                : "Action items will be extracted when you generate a summary.")),
                    actionLabel: meeting.segments.isEmpty
                        ? (!recorder.isRecording && !recorder.isStartingRecording ? "Start Meeting" : nil)
                        : (extractionMessage != nil ? "Try Again" : (hasSummary ? "Extract Action Items" : "Generate Summary")),
                    action: meeting.segments.isEmpty
                        ? (!recorder.isRecording && !recorder.isStartingRecording ? {
                            Task { await recorder.startRecording(for: meeting) }
                        } : nil)
                        : (isExtracting ? nil : {
                            extractionMessage = nil
                            if let smartMinutes = meeting.smartMinutes, !smartMinutes.actionItems.isEmpty {
                                let items = smartMinutes.actionItems.map { ActionItem(title: $0) }
                                store.setActionItems(items, for: meeting.id)
                            } else {
                                Task {
                                    let result = await store.generateAISummary(for: meeting.id)
                                    switch result {
                                    case .success:
                                        break // Action items will appear via observation
                                    case .noActionItems:
                                        extractionMessage = "No action items were found in this meeting's transcript. You can try again."
                                    case let .failed(error):
                                        extractionMessage = "Failed to extract action items: \(error)"
                                    case .skipped:
                                        extractionMessage = "AI model is not loaded. Please check Settings → Models."
                                    }
                                }
                            }
                        })
                )
            } else {
                VStack(spacing: 0) {
                    actionItemsControlsBar
                    Divider()

                    List {
                        Section {
                            ForEach(meeting.actionItems) { item in
                                ActionItemRow(
                                    item: item,
                                    meetingID: meeting.id,
                                    meetingTitle: meeting.title
                                )
                                .listRowSeparator(.visible)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(AppThemeConstants.surfaceBackground)
        .task {
            if meeting.actionItems.isEmpty,
               let smartMinutes = meeting.smartMinutes,
               !smartMinutes.actionItems.isEmpty
            {
                let items = smartMinutes.actionItems.map { ActionItem(title: $0) }
                store.setActionItems(items, for: meeting.id)
            }
        }
    }

    private var completedCount: Int {
        meeting.actionItems.filter(\.isCompleted).count
    }

    // MARK: - Top Controls Bar

    private var actionItemsControlsBar: some View {
        HStack(spacing: 8) {
            Text("\(completedCount)/\(meeting.actionItems.count) completed")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if isLiveRecording {
                if isExtracting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        extractionMessage = nil
                        Task {
                            let result = await store.generateAISummary(for: meeting.id)
                            switch result {
                            case .success:
                                break
                            case .noActionItems:
                                extractionMessage = "No new action items found in the latest transcript."
                            case let .failed(error):
                                extractionMessage = "Failed to update action items: \(error)"
                            case .skipped:
                                extractionMessage = "AI model is not loaded. Please check Settings → Models."
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                            Text("Update")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isExtracting || recorder.postRecordingPipeline.isGeneratingAISummary)
                    .help("Re-extract action items with latest transcript")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Action Item Row

private struct ActionItemRow: View {
    @Environment(MeetingStore.self) private var store
    let item: ActionItem
    let meetingID: UUID
    let meetingTitle: String

    @State private var showDatePicker = false
    @State private var showReminderPicker = false
    @State private var selectedDueDate = Date()
    @State private var selectedReminderDate = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleActionItemCompleted(itemID: item.id, in: meetingID)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(item.isCompleted ? AppThemeConstants.success : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                // Metadata: assignee + due date on line 1, reminder on line 2
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let assignee = item.assignee {
                            Label(assignee, systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !item.isCompleted {
                            dueDateControl
                        } else if let due = item.dueDescription, item.dueDate == nil {
                            Label(due, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !item.isCompleted {
                        reminderControl
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Due Date Control

    @ViewBuilder
    private var dueDateControl: some View {
        if let dueDate = item.dueDate {
            Button {
                selectedDueDate = dueDate
                showDatePicker = true
            } label: {
                Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(dueDateColor(dueDate).opacity(AppThemeConstants.activeOpacity), in: Capsule())
                    .foregroundStyle(dueDateColor(dueDate))
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                dueDatePopover
            }
        } else {
            Button {
                selectedDueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                showDatePicker = true
            } label: {
                Label("Set due date", systemImage: "calendar.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                dueDatePopover
            }
        }
    }

    // MARK: - Reminder Control

    @ViewBuilder
    private var reminderControl: some View {
        if let reminderDate = item.reminderDate {
            Button {
                selectedReminderDate = reminderDate
                showReminderPicker = true
            } label: {
                Label(reminderDate.formatted(date: .abbreviated, time: .shortened), systemImage: "bell.fill")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppThemeConstants.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(AppThemeConstants.accent)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reminder set for \(reminderDate.formatted(date: .abbreviated, time: .shortened))")
            .popover(isPresented: $showReminderPicker, arrowEdge: .bottom) {
                reminderPopover
            }
        } else {
            Button {
                if let dueDate = item.dueDate {
                    selectedReminderDate = dueDate.addingTimeInterval(-3600)
                } else {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                    selectedReminderDate = Calendar.current.date(
                        bySettingHour: 9, minute: 0, second: 0, of: tomorrow
                    ) ?? tomorrow
                }
                showReminderPicker = true
            } label: {
                Image(systemName: "bell")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Set reminder")
            .accessibilityLabel("Set reminder")
            .popover(isPresented: $showReminderPicker, arrowEdge: .bottom) {
                reminderPopover
            }
        }
    }

    // MARK: - Due Date Popover

    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Due Date")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                dueDatePreset("Today", date: Calendar.current.date(
                    bySettingHour: 17, minute: 0, second: 0, of: .now
                ))
                dueDatePreset("Tomorrow", date: Calendar.current.date(
                    bySettingHour: 9, minute: 0, second: 0,
                    of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                ))
                dueDatePreset("Next Week", date: Calendar.current.date(
                    byAdding: .weekOfYear, value: 1, to: .now
                ))
            }

            Divider()

            DatePicker("Custom:", selection: $selectedDueDate, displayedComponents: [.date])
                .datePickerStyle(.field)
                .font(.caption)

            HStack {
                if item.dueDate != nil {
                    Button("Remove") {
                        store.setActionItemDueDate(nil, itemID: item.id, in: meetingID)
                        showDatePicker = false
                    }
                    .foregroundStyle(AppThemeConstants.error)
                }

                Spacer()

                Button("Set") {
                    store.setActionItemDueDate(selectedDueDate, itemID: item.id, in: meetingID)
                    showDatePicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.small)
            }
        }
        .padding(AppThemeConstants.paddingMedium)
        .frame(width: 260)
    }

    private func dueDatePreset(_ label: String, date: Date?) -> some View {
        Button(label) {
            if let date {
                store.setActionItemDueDate(date, itemID: item.id, in: meetingID)
                showDatePicker = false
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Reminder Popover

    private var reminderPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminder")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 4) {
                reminderPreset("In 1 hour", date: Date.now.addingTimeInterval(3600))
                reminderPreset("In 3 hours", date: Date.now.addingTimeInterval(10800))
                reminderPreset("Tomorrow 9 AM", date: Calendar.current.date(
                    bySettingHour: 9, minute: 0, second: 0,
                    of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                ))
                if let dueDate = item.dueDate, dueDate > Date.now.addingTimeInterval(3600) {
                    reminderPreset(
                        "1h before due",
                        date: dueDate.addingTimeInterval(-3600)
                    )
                }
            }

            Divider()

            DatePicker("Custom:", selection: $selectedReminderDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
                .font(.caption)

            HStack {
                if item.reminderDate != nil {
                    Button("Remove") {
                        store.cancelActionItemReminder(itemID: item.id, in: meetingID)
                        showReminderPicker = false
                    }
                    .foregroundStyle(AppThemeConstants.error)
                }

                Spacer()

                Button("Set") {
                    store.setActionItemReminder(
                        itemID: item.id,
                        in: meetingID,
                        reminderDate: selectedReminderDate
                    )
                    showReminderPicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
                .controlSize(.small)
            }
        }
        .padding(AppThemeConstants.paddingMedium)
        .frame(width: 260)
    }

    private func reminderPreset(_ label: String, date: Date?) -> some View {
        Button {
            if let date {
                store.setActionItemReminder(
                    itemID: item.id,
                    in: meetingID,
                    reminderDate: date
                )
                showReminderPicker = false
            }
        } label: {
            HStack {
                Image(systemName: "bell")
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func dueDateColor(_ date: Date) -> Color {
        let now = Date.now
        if date < now {
            return AppThemeConstants.error
        }
        if date < now.addingTimeInterval(86400) {
            return AppThemeConstants.warning
        }
        return AppThemeConstants.brandPrimary
    }
}
