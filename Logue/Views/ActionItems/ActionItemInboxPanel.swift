import SwiftUI

/// The triage inbox for action items the model pulled out of meetings, as a panel of the
/// All Meetings surface.
///
/// Always global: every undecided item across every live meeting. Selecting a meeting in the
/// list behind this panel navigates to that meeting, so there is no selection for the panel
/// to follow — narrowing to one meeting is an explicit choice made here, in the picker.
struct ActionItemInboxPanel: View {
    @Environment(MeetingStore.self) private var meetingStore
    @State private var taskStore = TaskStore.shared

    @State private var searchText = ""
    @State private var meetingFilter: UUID?
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
        allItems
            .filter { matchesFilter($0) && matchesMeeting($0) && matchesSearch($0) }
            .sorted(by: sortOrder)
    }

    private func matchesFilter(_ item: DashboardActionItem) -> Bool {
        ActionItemInbox.matches(
            item.actionItem,
            mode: inboxMode,
            isPromoted: taskStore.promotedTask(for: item.actionItem.id) != nil
        )
    }

    private func matchesMeeting(_ item: DashboardActionItem) -> Bool {
        guard let meetingFilter else { return true }
        return item.meetingID == meetingFilter
    }

    private func matchesSearch(_ item: DashboardActionItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        return item.actionItem.title.localizedCaseInsensitiveContains(searchText)
            || item.meetingTitle.localizedCaseInsensitiveContains(searchText)
            || (item.actionItem.assignee?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private var counts: [ActionItemInboxMode: Int] {
        ActionItemInbox.counts(allItems.map(\.actionItem)) { item in
            taskStore.promotedTask(for: item.id) != nil
        }
    }

    /// The meetings that actually have action items, so the picker is not a list of
    /// everything the user has ever recorded.
    private var meetingsWithItems: [(id: UUID, title: String)] {
        var seen = Set<UUID>()
        var result: [(id: UUID, title: String)] = []
        for item in allItems where seen.insert(item.meetingID).inserted {
            result.append((item.meetingID, item.meetingTitle))
        }
        return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchBarField(text: $searchText, placeholder: "Search action items", expandable: true)
            chipBar
            HStack(spacing: 6) {
                meetingPicker
                Spacer()
                addAllButton
                sortMenu
            }
        }
        .padding(.horizontal, AppThemeConstants.paddingLarge)
        .padding(.vertical, 10)
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActionItemInboxMode.allCases, id: \.rawValue) { mode in
                    let count = counts[mode] ?? 0
                    FilterChip(
                        label: "\(mode.displayName) \(count)",
                        isSelected: inboxMode == mode,
                        tintColor: mode == .dismissed ? AppThemeConstants.warning : nil
                    ) {
                        inboxModeRaw = mode.rawValue
                    }
                    .accessibilityLabel("\(mode.displayName), \(count) items")
                }
            }
        }
    }

    private var meetingPicker: some View {
        Menu {
            Button("All meetings") { meetingFilter = nil }
            Divider()
            ForEach(meetingsWithItems, id: \.id) { meeting in
                Button(meeting.title) { meetingFilter = meeting.id }
            }
        } label: {
            Label(meetingFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
                .lineLimit(1)
        }
        .controlSize(.small)
        .fixedSize()
        .help("Show items from one meeting")
    }

    private var meetingFilterLabel: String {
        guard let meetingFilter,
              let match = meetingsWithItems.first(where: { $0.id == meetingFilter })
        else { return "All meetings" }
        return match.title
    }

    /// The items shown that are not already on the task list.
    private var promotableItems: [DashboardActionItem] {
        filteredItems.filter { taskStore.promotedTask(for: $0.actionItem.id) == nil }
    }

    private var addAllButton: some View {
        Button {
            for item in promotableItems {
                taskStore.promote(item.actionItem, from: item.meetingID)
            }
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        // Promotion is idempotent, so pressing twice is safe by construction; disabled when
        // there is nothing left to add so the press has a visible effect.
        .disabled(promotableItems.isEmpty)
        .help("Add every action item shown to your tasks")
        .accessibilityLabel("Add all to Tasks")
    }

    private var sortMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .controlSize(.small)
        .fixedSize()
        .help("Sort")
        .accessibilityLabel("Sort action items")
    }

    // MARK: - List

    private var itemsList: some View {
        List {
            ForEach(filteredItems) { item in
                ActionItemInboxRow(item: item)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: emptyIcon,
            title: emptyTitle,
            description: emptyDescription
        )
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No Matching Items" }
        switch inboxMode {
        case .inbox: return "Inbox Zero"
        case .dismissed: return "Nothing Dismissed"
        case .all: return "No Action Items Yet"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return inboxMode == .inbox ? "tray" : "checklist"
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "No action items match \"\(searchText)\"" }
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
