import SwiftUI

// MARK: - Sort Options

enum ActionItemSortOrder: String, CaseIterable {
    case dueDateAsc = "Due Date (Soonest)"
    case dueDateDesc = "Due Date (Latest)"
    case createdNewest = "Recently Added"
    case createdOldest = "Oldest First"
    case meetingTitle = "Meeting Title"
    case status = "Status"
}

// MARK: - Dashboard Action Item (aggregated view model)

/// A single action item with its meeting context, used by the dashboard.
struct DashboardActionItem: Identifiable, Hashable {
    let actionItem: ActionItem
    let meetingID: UUID
    let meetingTitle: String

    var id: UUID {
        actionItem.id
    }

    static func == (lhs: DashboardActionItem, rhs: DashboardActionItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension DashboardActionItem {
    enum Urgency {
        case completed
        case overdue
        case dueToday
        case dueThisWeek
        case upcoming
        case noDate

        var color: Color {
            switch self {
            case .completed: AppThemeConstants.success
            case .overdue: AppThemeConstants.error
            case .dueToday: AppThemeConstants.warning
            case .dueThisWeek: AppThemeConstants.warning
            case .upcoming: AppThemeConstants.accent
            case .noDate: .secondary
            }
        }
    }

    var urgency: Urgency {
        if actionItem.isCompleted {
            return .completed
        }
        guard let due = actionItem.dueDate else { return .noDate }
        let now = Date()
        let calendar = Calendar.current
        let startOfTomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        let startOfNextWeek = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 7, to: now) ?? now
        )
        if due < now {
            return .overdue
        }
        if due < startOfTomorrow {
            return .dueToday
        }
        if due < startOfNextWeek {
            return .dueThisWeek
        }
        return .upcoming
    }
}

// MARK: - ActionItemDashboardView

/// The triage inbox for action items the model pulled out of meetings.
///
/// Not a second task list. Everything here is awaiting one decision — promote it into Tasks
/// or dismiss it — and anything decided leaves. The due-date vocabulary this screen used to
/// carry now lives on the Tasks surface, which is where work the user accepted belongs.
struct ActionItemDashboardView: View {
    @Environment(MeetingStore.self) private var meetingStore
    @State private var taskStore = TaskStore.shared

    @State private var searchText = ""
    @AppStorage(AppConstants.UserDefaultsKeys.actionItemInboxMode)
    private var inboxModeRaw = ActionItemInboxMode.inbox.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.actionItemSortOrder)
    private var sortOrderRaw = ActionItemSortOrder.dueDateAsc.rawValue

    private var inboxMode: ActionItemInboxMode {
        ActionItemInboxMode(rawValue: inboxModeRaw) ?? .inbox
    }

    private var sortOrder: ActionItemSortOrder {
        ActionItemSortOrder(rawValue: sortOrderRaw) ?? .dueDateAsc
    }

    // MARK: - Aggregation

    private var allItems: [DashboardActionItem] {
        var result: [DashboardActionItem] = []
        for meeting in meetingStore.activeMeetings where !meeting.isArchived {
            for item in meeting.actionItems {
                result.append(DashboardActionItem(
                    actionItem: item,
                    meetingID: meeting.id,
                    meetingTitle: meeting.title
                ))
            }
        }
        return result
    }

    private var filteredItems: [DashboardActionItem] {
        let filtered = allItems.filter { item in
            matchesFilter(item) && matchesSearch(item)
        }
        return sorted(filtered)
    }

    private func matchesFilter(_ item: DashboardActionItem) -> Bool {
        ActionItemInbox.matches(
            item.actionItem,
            mode: inboxMode,
            isPromoted: taskStore.promotedTask(for: item.actionItem.id) != nil
        )
    }

    private func matchesSearch(_ item: DashboardActionItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        return item.actionItem.title.localizedCaseInsensitiveContains(searchText)
            || item.meetingTitle.localizedCaseInsensitiveContains(searchText)
            || (item.actionItem.assignee?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private func sorted(_ items: [DashboardActionItem]) -> [DashboardActionItem] {
        switch sortOrder {
        case .dueDateAsc:
            items.sorted { lhs, rhs in
                (lhs.actionItem.dueDate ?? .distantFuture)
                    < (rhs.actionItem.dueDate ?? .distantFuture)
            }
        case .dueDateDesc:
            items.sorted { lhs, rhs in
                (lhs.actionItem.dueDate ?? .distantPast)
                    > (rhs.actionItem.dueDate ?? .distantPast)
            }
        case .createdNewest:
            items.sorted { $0.actionItem.createdAt > $1.actionItem.createdAt }
        case .createdOldest:
            items.sorted { $0.actionItem.createdAt < $1.actionItem.createdAt }
        case .meetingTitle:
            items.sorted {
                $0.meetingTitle.localizedCaseInsensitiveCompare($1.meetingTitle) == .orderedAscending
            }
        case .status:
            items.sorted { lhs, rhs in
                if lhs.actionItem.isCompleted != rhs.actionItem.isCompleted {
                    return !lhs.actionItem.isCompleted
                }
                return (lhs.actionItem.dueDate ?? .distantFuture)
                    < (rhs.actionItem.dueDate ?? .distantFuture)
            }
        }
    }

    // MARK: - Counts for filter chips

    private var counts: [ActionItemInboxMode: Int] {
        ActionItemInbox.counts(allItems.map(\.actionItem)) { item in
            taskStore.promotedTask(for: item.id) != nil
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            filterChipBar
            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Action Items")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search action items")
        .toolbar {
            toolbarContent
        }
    }

    private var subtitle: String {
        let total = filteredItems.count
        if inboxMode == .inbox {
            return "\(total) in inbox"
        }
        return "\(total) item\(total == 1 ? "" : "s")"
    }

    // MARK: - Toolbar

    /// The items shown that are not already on the task list.
    private var promotableItems: [DashboardActionItem] {
        filteredItems.filter { taskStore.promotedTask(for: $0.actionItem.id) == nil }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                for item in promotableItems {
                    taskStore.promote(item.actionItem, from: item.meetingID)
                }
            } label: {
                Image(systemName: "text.badge.plus")
            }
            // Promotion is idempotent, so pressing this twice is safe by construction; it is
            // disabled when there is nothing left to add so the press has a visible effect.
            .disabled(promotableItems.isEmpty)
            .help("Add every action item shown to your tasks")
            .accessibilityLabel("Add all to Tasks")

            Menu {
                Section("Sort By") {
                    ForEach(ActionItemSortOrder.allCases, id: \.rawValue) { order in
                        Button {
                            sortOrderRaw = order.rawValue
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
            .help("Sort")
            .accessibilityLabel("Sort action items")
        }
    }

    // MARK: - Filter Chip Bar

    private var filterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActionItemInboxMode.allCases, id: \.rawValue) { mode in
                    let count = counts[mode] ?? 0
                    FilterChip(
                        label: "\(mode.displayName) \(count)",
                        isSelected: inboxMode == mode,
                        tintColor: tintColor(for: mode)
                    ) {
                        inboxModeRaw = mode.rawValue
                    }
                    .accessibilityLabel("\(mode.displayName), \(count) items")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func tintColor(for mode: ActionItemInboxMode) -> Color? {
        switch mode {
        case .dismissed: AppThemeConstants.warning
        default: nil
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    ActionItemInboxRow(item: item)
                    if item.id != filteredItems.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
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
            return "No Matching Items"
        }
        switch inboxMode {
        case .inbox: return "Inbox Zero"
        case .dismissed: return "Nothing Dismissed"
        case .all: return "No Action Items Yet"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        return inboxMode == .inbox ? "tray" : "checklist"
    }

    private var emptyDescription: String {
        if !searchText.isEmpty {
            return "No action items match \"\(searchText)\""
        }
        switch inboxMode {
        case .inbox:
            return "Every action item Logue found has been added to your tasks or dismissed."
        case .dismissed:
            return "Items you decide aren't worth acting on will appear here."
        case .all:
            return "Action items extracted from meetings will appear here."
        }
    }
}
