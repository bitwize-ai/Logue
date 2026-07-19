import SwiftUI

// MARK: - Filter & Sort Options

enum ActionItemFilterMode: String, CaseIterable {
    case all = "All"
    case pending = "Pending"
    case overdue = "Overdue"
    case dueToday = "Due Today"
    case dueThisWeek = "This Week"
    case noDueDate = "No Due Date"
    case completed = "Completed"

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .pending: "circle"
        case .overdue: "exclamationmark.triangle"
        case .dueToday: "calendar"
        case .dueThisWeek: "calendar.badge.clock"
        case .noDueDate: "calendar.badge.exclamationmark"
        case .completed: "checkmark.circle"
        }
    }
}

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

/// Cross-meeting dashboard aggregating all action items with filter, sort, and search.
/// Backend already exists via `MeetingStore` mutations; this surfaces items in one place
/// so users can triage accountability without visiting each meeting.
struct ActionItemDashboardView: View {
    @Environment(MeetingStore.self) private var meetingStore

    @State private var searchText = ""
    @State private var filterMode: ActionItemFilterMode = .pending
    @AppStorage(AppConstants.UserDefaultsKeys.actionItemSortOrder)
    private var sortOrderRaw = ActionItemSortOrder.dueDateAsc.rawValue

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
        switch filterMode {
        case .all:
            true
        case .pending:
            !item.actionItem.isCompleted
        case .overdue:
            item.urgency == .overdue
        case .dueToday:
            item.urgency == .dueToday
        case .dueThisWeek:
            item.urgency == .dueThisWeek || item.urgency == .dueToday || item.urgency == .overdue
        case .noDueDate:
            !item.actionItem.isCompleted && item.actionItem.dueDate == nil
        case .completed:
            item.actionItem.isCompleted
        }
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

    private var counts: [ActionItemFilterMode: Int] {
        var dict: [ActionItemFilterMode: Int] = [:]
        let items = allItems
        dict[.all] = items.count
        dict[.pending] = items.filter { !$0.actionItem.isCompleted }.count
        dict[.overdue] = items.filter { $0.urgency == .overdue }.count
        dict[.dueToday] = items.filter { $0.urgency == .dueToday }.count
        dict[.dueThisWeek] = items.filter {
            $0.urgency == .dueToday || $0.urgency == .dueThisWeek || $0.urgency == .overdue
        }.count
        dict[.noDueDate] = items.filter {
            !$0.actionItem.isCompleted && $0.actionItem.dueDate == nil
        }.count
        dict[.completed] = items.filter(\.actionItem.isCompleted).count
        return dict
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
        return "\(total) item\(total == 1 ? "" : "s")"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
                ForEach(ActionItemFilterMode.allCases, id: \.rawValue) { mode in
                    let count = counts[mode] ?? 0
                    FilterChip(
                        label: "\(mode.rawValue) \(count)",
                        isSelected: filterMode == mode,
                        tintColor: tintColor(for: mode)
                    ) {
                        filterMode = mode
                    }
                    .accessibilityLabel("\(mode.rawValue), \(count) items")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func tintColor(for mode: ActionItemFilterMode) -> Color? {
        switch mode {
        case .overdue: AppThemeConstants.error
        case .dueToday, .dueThisWeek: AppThemeConstants.warning
        case .completed: AppThemeConstants.success
        default: nil
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    ActionItemDashboardRow(item: item)
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
        switch filterMode {
        case .all: return "No Action Items Yet"
        case .pending: return "All Caught Up"
        case .overdue: return "Nothing Overdue"
        case .dueToday: return "Nothing Due Today"
        case .dueThisWeek: return "Nothing Due This Week"
        case .noDueDate: return "All Items Have Due Dates"
        case .completed: return "No Completed Items"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        switch filterMode {
        case .overdue, .dueToday, .dueThisWeek: return "checkmark.circle"
        case .completed: return "circle"
        default: return "checklist"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty {
            return "No action items match \"\(searchText)\""
        }
        switch filterMode {
        case .all: return "Action items extracted from meetings will appear here."
        case .pending: return "Every action item is either completed or scheduled. Nice work."
        case .overdue: return "No action items are past their due date."
        case .dueToday: return "No action items are due today."
        case .dueThisWeek: return "No action items are due in the next seven days."
        case .noDueDate: return "Every pending item has a due date assigned."
        case .completed: return "Completed items will appear here once you mark them done."
        }
    }
}

// MARK: - Dashboard Row

/// A single row in the Action Item Dashboard.
private struct ActionItemDashboardRow: View {
    let item: DashboardActionItem
    @Environment(MeetingStore.self) private var meetingStore
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            completionButton

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
            isHovered
                ? AppThemeConstants.surfaceBackground
                : Color.clear,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            openMeeting()
        }
        .contextMenu {
            Button {
                openMeeting()
            } label: {
                Label("Open Meeting", systemImage: "arrow.up.right.square")
            }
            Button {
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
        }
        // Accessibility: `.combine` was flattening + stripping the explicit label in macOS 26
        // SwiftUI. `.contain` keeps inner buttons individually reachable (completion toggle,
        // meeting link); the explicit label + isButton trait + primary action expose the row
        // itself as a named, activatable AXButton.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            openMeeting()
        }
    }

    private var completionButton: some View {
        Button {
            HapticFeedback.levelChange()
            meetingStore.toggleActionItemCompleted(
                itemID: item.actionItem.id,
                in: item.meetingID
            )
        } label: {
            Image(systemName: item.actionItem.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    item.actionItem.isCompleted
                        ? AppThemeConstants.success
                        : .secondary
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.actionItem.isCompleted ? "Mark incomplete" : "Mark complete")
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
