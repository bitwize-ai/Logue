import AppKit
import SwiftUI

/// The Tasks surface: capture at the top, filter and sort controls, the list below.
struct TaskListView: View {
    @State private var store = TaskStore.shared
    @State private var meetingStore = MeetingStore.shared

    @AppStorage(AppConstants.UserDefaultsKeys.taskFilterMode)
    private var filterModeRaw = TaskFilterMode.all.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.taskSortOrder)
    private var sortOrderRaw = TaskSortOrder.dueDateAsc.rawValue

    @State private var selectedTag: String?
    @State private var triageService = TaskTriageService.shared
    @State private var engineStatus = LLMEngineStatus.shared
    @State private var showTriage = false

    private var filterMode: TaskFilterMode {
        TaskFilterMode(rawValue: filterModeRaw) ?? .all
    }

    private var sortOrder: TaskSortOrder {
        TaskSortOrder(rawValue: sortOrderRaw) ?? .dueDateAsc
    }

    private var visibleTasks: [TaskItem] {
        TaskFilter.sort(
            TaskFilter.apply(store.tasks, mode: filterMode, tag: selectedTag),
            by: sortOrder
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskQuickAddField { text in
                store.capture(text)
            }

            controls

            if visibleTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .padding(16)
        .navigationTitle("Tasks")
        .sheet(isPresented: $showTriage) {
            triageSheet
        }
    }

    private var triageSheet: some View {
        VStack(alignment: .trailing, spacing: 0) {
            TaskTriagePanelView()
            Button("Done") {
                showTriage = false
                triageService.clear()
            }
            .keyboardShortcut(.defaultAction)
            .padding([.trailing, .bottom], 16)
        }
    }

    private var triageButton: some View {
        Button {
            showTriage = true
            Task {
                await triageService.run(tasks: store.tasks, knownTags: store.allTags)
            }
        } label: {
            Label("Triage", systemImage: "sparkles")
        }
        // Concurrent inference races on the shared session; this is the project-wide guard
        // for any control that reaches the engine.
        .disabled(engineStatus.isBusy || store.openTasks.isEmpty)
        .help("Ask Logue to review your open tasks")
    }

    private var taskList: some View {
        List {
            ForEach(visibleTasks) { task in
                TaskRowView(
                    task: task,
                    meetingTitle: meetingTitle(for: task),
                    onToggle: { store.toggleCompletion(id: task.id) },
                    onOpenSource: { openSource(for: task) }
                )
                .contextMenu {
                    priorityMenu(for: task)
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(id: task.id) }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func priorityMenu(for task: TaskItem) -> some View {
        Menu("Priority") {
            ForEach(TaskPriority.allCases, id: \.rawValue) { priority in
                Button {
                    var updated = task
                    updated.priority = priority
                    store.update(updated)
                } label: {
                    Label(priority.displayName, systemImage: priority.symbolName)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Picker("Filter", selection: $filterModeRaw) {
                ForEach(TaskFilterMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()

            triageButton
            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrderRaw) {
                ForEach(TaskSortOrder.allCases, id: \.rawValue) { order in
                    Text(order.displayName).tag(order.rawValue)
                }
            }
            if !store.allTags.isEmpty {
                Divider()
                Button("All tags") { selectedTag = nil }
                ForEach(store.allTags, id: \.self) { tag in
                    Button(tag) { selectedTag = tag }
                }
            }
        } label: {
            Label("Sort and filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Nothing here")
                .font(.headline)
            Text("Type above to add a task. Try \"Send the deck tomorrow #launch !\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meetingTitle(for task: TaskItem) -> String? {
        guard let id = task.sourceMeetingID else { return nil }
        return meetingStore.meetings.first { $0.id == id }?.title
    }

    /// Built through `DeepLink` rather than by assembling a string, so the scheme and host
    /// stay in one place.
    private func openSource(for task: TaskItem) {
        guard let id = task.sourceMeetingID else { return }
        NSWorkspace.shared.open(DeepLink.meeting(id: id).url)
    }
}
