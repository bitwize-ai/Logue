import AppKit
import SwiftUI

/// The Tasks surface: capture at the top, the app's filter chips and toolbar, the list below.
///
/// Shares its chrome with the action item inbox on purpose — the two screens are one idea
/// (what the model found, and what you accepted), and a red chip means the same thing on
/// both.
struct TaskListView: View {
    @State private var store = TaskStore.shared
    @State private var meetingStore = MeetingStore.shared

    @AppStorage(AppConstants.UserDefaultsKeys.taskFilterMode)
    private var filterModeRaw = TaskFilterMode.all.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.taskSortOrder)
    private var sortOrderRaw = TaskSortOrder.dueDateAsc.rawValue

    @State private var searchText = ""
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
            TaskFilter.apply(
                store.tasks, mode: filterMode, tag: selectedTag, searchText: searchText
            ),
            by: sortOrder
        )
    }

    private var counts: [TaskFilterMode: Int] {
        var result: [TaskFilterMode: Int] = [:]
        for mode in TaskFilterMode.allCases {
            result[mode] = TaskFilter.apply(store.tasks, mode: mode, tag: selectedTag).count
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            TaskQuickAddField { text in
                store.capture(text)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            filterChipBar
            Divider()

            if visibleTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Tasks")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search tasks")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showTriage) {
            triageSheet
        }
    }

    private var subtitle: String {
        let total = visibleTasks.count
        return "\(total) task\(total == 1 ? "" : "s")"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showTriage = true
                Task {
                    await triageService.run(tasks: store.tasks, knownTags: store.allTags)
                }
            } label: {
                Image(systemName: "sparkles")
            }
            // Concurrent inference races on the shared session; this is the project-wide
            // guard for any control that reaches the engine.
            .disabled(engineStatus.isBusy || store.openTasks.isEmpty)
            .help("Ask Logue to review your open tasks")
            .accessibilityLabel("Triage tasks")

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
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .help("Sort and filter")
        .accessibilityLabel("Sort tasks")
    }

    // MARK: - Filter Chip Bar

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskFilterMode.allCases, id: \.rawValue) { mode in
                    let count = counts[mode] ?? 0
                    FilterChip(
                        label: "\(mode.displayName) \(count)",
                        isSelected: filterMode == mode,
                        tintColor: tintColor(for: mode)
                    ) {
                        filterModeRaw = mode.rawValue
                    }
                    .accessibilityLabel("\(mode.displayName), \(count) tasks")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    /// The same mapping the action item chips use, so a red chip means the same thing on
    /// both screens.
    private func tintColor(for mode: TaskFilterMode) -> Color? {
        switch mode {
        case .overdue: AppThemeConstants.error
        case .today, .upcoming: AppThemeConstants.warning
        case .completed: AppThemeConstants.success
        default: nil
        }
    }

    // MARK: - List

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                    if task.id != visibleTasks.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
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

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptyIcon)
        } description: {
            Text(emptyDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty {
            return "No Matching Tasks"
        }
        switch filterMode {
        case .all: return "Nothing Here"
        case .today: return "Nothing Due Today"
        case .overdue: return "Nothing Overdue"
        case .upcoming: return "Nothing Upcoming"
        case .noDueDate: return "Every Task Has a Date"
        case .completed: return "No Completed Tasks"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        switch filterMode {
        case .overdue, .today, .upcoming: return "checkmark.circle"
        case .completed: return "circle"
        default: return "checklist"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty {
            return "No tasks match \"\(searchText)\""
        }
        switch filterMode {
        case .all: return "Type above to add a task. Try \"Send the deck tomorrow #launch !\"."
        case .today: return "Nothing is due today."
        case .overdue: return "No task is past its due date."
        case .upcoming: return "Nothing is scheduled ahead."
        case .noDueDate: return "Every open task has a due date."
        case .completed: return "Completed tasks will appear here."
        }
    }

    // MARK: - Source Meeting

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
