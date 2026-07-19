import SwiftUI

/// Full-width content view that lists meetings, used when
/// "All Meetings" is selected in the sidebar.
struct MeetingListContentView: View {
    let spaceID: UUID?
    @Environment(MeetingStore.self) private var store
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var ftsMatchingIDs: Set<UUID> = []
    @State private var filterMode: MeetingFilterMode = .all
    @AppStorage(AppConstants.UserDefaultsKeys.meetingSortOrder) private var sortOrderRaw = MeetingSortOrder.modifiedNewest.rawValue
    @State private var selectedTagFilter: String?
    @State private var showRenameAlert = false
    @State private var renamingMeetingID: UUID?
    @State private var renameText = ""
    @Environment(CalendarManager.self) private var calendarManager
    @AppStorage(AppConstants.UserDefaultsKeys.meetingViewMode) private var viewModeRaw = ContentViewMode.list.rawValue

    private var viewMode: ContentViewMode {
        ContentViewMode(rawValue: viewModeRaw) ?? .list
    }

    @AppStorage(AppConstants.UserDefaultsKeys.groupByDate) private var groupByDate = true

    private var sortOrder: MeetingSortOrder {
        get { MeetingSortOrder(rawValue: sortOrderRaw) ?? .modifiedNewest }
        set { sortOrderRaw = newValue.rawValue }
    }

    private var groupedMeetings: [DateGroupingHelper.Group<MeetingNote>]? {
        guard groupByDate, sortOrder.isDateBased, let kp = sortOrder.dateKeyPath else { return nil }
        let groups = DateGroupingHelper.group(filteredMeetings, by: kp)
        return groups.isEmpty ? nil : groups
    }

    // MARK: - Filtered Meetings

    private var filteredMeetings: [MeetingNote] {
        let active = store.activeMeetings
        let base: [MeetingNote] = if let spaceID {
            active.filter { $0.spaceID == spaceID && !$0.isArchived }
        } else {
            switch filterMode {
            case .all: active.filter { !$0.isArchived }
            case .pinned: store.pinnedMeetings
            case .recent: store.recentMeetings
            case .archived: store.archivedMeetings
            case .voiceNotes: active.filter { !$0.isArchived && $0.recordingMode == .voiceNote }
            }
        }

        let tagged: [MeetingNote] = if let tag = selectedTagFilter {
            base.filter { $0.tags.contains(tag) }
        } else {
            base
        }

        let searched: [MeetingNote] = if debouncedSearchText.isEmpty {
            tagged
        } else {
            tagged.filter {
                $0.title.localizedCaseInsensitiveContains(debouncedSearchText)
                    || ($0.summary?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false)
                    || ftsMatchingIDs.contains($0.id)
            }
        }

        return sorted(searched)
    }

    private func sorted(_ meetings: [MeetingNote]) -> [MeetingNote] {
        let base: [MeetingNote] = switch sortOrder {
        case .modifiedNewest: meetings.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest: meetings.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAZ: meetings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA: meetings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .createdNewest: meetings.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: meetings.sorted { $0.createdAt < $1.createdAt }
        case .longest: meetings.sorted { $0.duration > $1.duration }
        case .shortest: meetings.sorted { $0.duration < $1.duration }
        }
        // Pin favorited meetings to the top while preserving sort order within each group
        return base.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return false
        }
    }

    private var title: String {
        if let spaceID, let space = spaceStore.space(for: spaceID) {
            return space.name
        }
        return "All Meetings"
    }

    private var hasUpcomingEvents: Bool {
        spaceID == nil && calendarManager.isEnabled && !calendarManager.upcomingEvents.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !store.allTags.isEmpty, spaceID == nil {
                tagFilterBar
                Divider()
            }

            if filteredMeetings.isEmpty, !hasUpcomingEvents {
                emptyState
            } else if viewMode == .grid {
                meetingGrid
            } else {
                meetingList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .onDisappear { searchDebounceTask?.cancel() }
        .alert("Rename Meeting", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let id = renamingMeetingID {
                    store.renameMeeting(id: id, newTitle: renameText)
                }
                renamingMeetingID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingMeetingID = nil
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(filteredMeetings.count) meeting\(filteredMeetings.count == 1 ? "" : "s")")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search meetings")
        .refreshable {
            // Exposes macOS's "Refresh" menu item + Cmd-R binding.
            // Calendar events are the only async source-of-truth in this view;
            // meetings themselves stream live from MeetingStore.
            await refreshCalendarEvents()
        }
        .toolbar {
            meetingListToolbarContent
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                ftsMatchingIDs = []
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.searchDebounce)
                    guard !Task.isCancelled else { return }
                    let ids = await MeetingMemoryIndex.shared.searchMatchingIDs(query: newValue)
                    guard !Task.isCancelled else { return }
                    ftsMatchingIDs = ids
                    debouncedSearchText = newValue
                }
            }
        }
        .onAppear {
            calendarManager.refreshUpcomingEvents()
        }
    }

    /// Triggered by macOS's refresh affordances (pull-to-refresh, Cmd-R, menu).
    /// Brief yield so the refresh indicator actually shows — `refreshUpcomingEvents`
    /// is synchronous internally and would otherwise complete instantly.
    private func refreshCalendarEvents() async {
        calendarManager.refreshUpcomingEvents()
        try? await Task.sleep(for: .milliseconds(400))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var meetingListToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                let meeting = store.createMeeting(
                    title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                    inSpace: spaceID
                )
                store.selectedMeetingID = meeting.id
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("New Meeting")
            }
            .help("New Meeting")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                if spaceID == nil {
                    Section("Filter") {
                        ForEach(MeetingFilterMode.allCases, id: \.rawValue) { mode in
                            Button {
                                filterMode = mode
                            } label: {
                                HStack {
                                    Label(mode.rawValue, systemImage: mode.icon)
                                    if filterMode == mode {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Sort By") {
                    ForEach(MeetingSortOrder.allCases, id: \.rawValue) { order in
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
                Image(systemName: "ellipsis.circle")
            }
            .help("Filter & Sort")
            .accessibilityLabel("Filter and Sort")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModeRaw = viewMode == .list
                        ? ContentViewMode.grid.rawValue
                        : ContentViewMode.list.rawValue
                }
            } label: {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
            }
            .help(viewMode == .list ? "Grid View" : "List View")
            .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")
        }
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: selectedTagFilter == nil) {
                    filterMode = .all
                    selectedTagFilter = nil
                }
                ForEach(store.allTags, id: \.self) { tag in
                    FilterChip(label: tag, isSelected: selectedTagFilter == tag, tintColor: AppThemeConstants.tagColor(for: tag)) {
                        filterMode = .all
                        selectedTagFilter = selectedTagFilter == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Meeting List

    private var meetingList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if hasUpcomingEvents {
                    upcomingEventsSection
                }

                if let groups = groupedMeetings {
                    ForEach(groups, id: \.label) { section in
                        dateGroupHeader(section.label)
                        ForEach(section.items) { meeting in
                            meetingRowView(meeting)
                        }
                    }
                } else {
                    ForEach(filteredMeetings) { meeting in
                        meetingRowView(meeting)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func meetingRowView(_ meeting: MeetingNote) -> some View {
        MeetingListRowView(
            meeting: meeting,
            store: store,
            spaceStore: spaceStore,
            onSelect: { store.selectedMeetingID = meeting.id },
            onRename: { beginRename(meeting) }
        )
    }

    private func dateGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    // MARK: - Grid

    private var meetingGrid: some View {
        let gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]
        return ScrollView {
            VStack(spacing: 0) {
                if hasUpcomingEvents {
                    upcomingEventsSection
                    Divider()
                        .padding(.horizontal, 24)
                }
            }

            if let groups = groupedMeetings {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.label) { section in
                        dateGroupHeader(section.label)
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(section.items) { meeting in
                                meetingGridCard(meeting)
                            }
                        }
                    }
                }
                .padding(24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredMeetings) { meeting in
                        meetingGridCard(meeting)
                    }
                }
                .padding(24)
            }
        }
    }

    private func meetingGridCard(_ meeting: MeetingNote) -> some View {
        MeetingGridCardView(
            meeting: meeting,
            store: store,
            spaceStore: spaceStore,
            onSelect: { store.selectedMeetingID = meeting.id },
            onRename: { beginRename(meeting) }
        )
    }

    // MARK: - Upcoming Events

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.accent)
                Text("Upcoming")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ForEach(calendarManager.upcomingEvents.prefix(3)) { event in
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.isHappeningNow ? AppThemeConstants.error : event.isStartingSoon ? AppThemeConstants.warning : AppThemeConstants
                            .accent.opacity(0.4))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                            Text("\u{00B7}")
                            Text("\(event.durationMinutes) min")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        startMeetingFromEvent(event)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "record.circle")
                                .font(.caption2)
                            Text("Record")
                                .font(.caption2.weight(.medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.accent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Spacer()
                .frame(height: 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptyIcon)
        } description: {
            if searchText.isEmpty {
                Text("Start a new meeting to begin recording.")
            } else {
                Text("No meetings match '\(searchText)'")
            }
        } actions: {
            if searchText.isEmpty {
                Button("New Meeting") {
                    tryCreateMeeting()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty {
            return "No Results"
        }
        switch filterMode {
        case .all: return "No Meetings"
        case .pinned: return "No Pinned Items"
        case .recent: return "No Recent Meetings"
        case .archived: return "No Archived Meetings"
        case .voiceNotes: return "No Voice Notes"
        }
    }

    private var emptyIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        switch filterMode {
        case .all: return "waveform"
        case .pinned: return "pin"
        case .recent: return "clock"
        case .archived: return "archivebox"
        case .voiceNotes: return "mic.badge.plus"
        }
    }

    // MARK: - Actions

    /// Creates a new meeting and opens it.
    private func tryCreateMeeting(template: MeetingTemplate = .general) {
        let meeting = store.createMeeting(
            title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            template: template,
            inSpace: spaceID
        )
        store.selectedMeetingID = meeting.id
    }

    private func beginRename(_ meeting: MeetingNote) {
        renameText = meeting.title
        renamingMeetingID = meeting.id
        showRenameAlert = true
    }

    private func startMeetingFromEvent(_ event: CalendarEvent) {
        var meeting = store.createMeeting(
            title: event.title,
            mode: .onlineMeeting,
            template: .general,
            inSpace: spaceID
        )
        meeting.calendarEventID = event.id
        meeting.scheduledStartTime = event.startDate
        store.updateMeeting(meeting)
        store.pendingAutoRecord = meeting.id
        store.selectedMeetingID = meeting.id
    }
}
