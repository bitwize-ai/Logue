import SwiftUI

// MARK: - Sort, Filter & View Options

enum MeetingSortOrder: String, CaseIterable {
    case modifiedNewest = "Last Modified"
    case modifiedOldest = "Oldest Modified"
    case titleAZ = "Title A–Z"
    case titleZA = "Title Z–A"
    case createdNewest = "Newest Created"
    case createdOldest = "Oldest Created"
    case longest = "Longest"
    case shortest = "Shortest"

    var icon: String {
        switch self {
        case .modifiedNewest, .createdNewest: "arrow.down"
        case .modifiedOldest, .createdOldest: "arrow.up"
        case .titleAZ: "textformat.abc"
        case .titleZA: "textformat.abc"
        case .longest: "timer"
        case .shortest: "timer"
        }
    }

    var isDateBased: Bool {
        switch self {
        case .modifiedNewest, .modifiedOldest, .createdNewest, .createdOldest: true
        case .titleAZ, .titleZA, .longest, .shortest: false
        }
    }

    var dateKeyPath: KeyPath<MeetingNote, Date>? {
        switch self {
        case .modifiedNewest, .modifiedOldest: \.modifiedAt
        case .createdNewest, .createdOldest: \.createdAt
        default: nil
        }
    }
}

enum MeetingFilterMode: String, CaseIterable {
    case all = "All Meetings"
    case pinned = "Pinned"
    case recent = "Recent"
    case archived = "Archived"
    case voiceNotes = "Voice Notes"

    var icon: String {
        switch self {
        case .all: "waveform"
        case .pinned: "pin"
        case .recent: "clock"
        case .archived: "archivebox"
        case .voiceNotes: "mic.badge.plus"
        }
    }
}

// MARK: - MeetingListPane

/// Column 2 content when Meetings category is selected.
/// Shows search, filter/sort/view menus, tag chips, upcoming events, and a selectable meeting list or gallery.
struct MeetingListPane: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedItem: ContentListItem?

    // Search & filter state
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var ftsMatchingIDs: Set<UUID> = []
    @State private var filterMode: MeetingFilterMode = .all
    @State private var sortOrder: MeetingSortOrder = .modifiedNewest
    @State private var selectedTagFilter: String?

    // Rename state
    @State private var renamingMeetingID: UUID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    /// Calendar
    @Environment(CalendarManager.self) private var calendarManager

    /// Auto-select
    @State private var hasAutoSelected = false

    // MARK: - Selected Meeting

    private var selectedMeeting: MeetingNote? {
        guard case let .meeting(id) = selectedItem else { return nil }
        return store.meetings.first { $0.id == id }
    }

    // MARK: - Filtered Meetings

    private var filteredMeetings: [MeetingNote] {
        let active = store.activeMeetings
        let base: [MeetingNote] = switch filterMode {
        case .all: active.filter { !$0.isArchived }
        case .pinned: store.pinnedMeetings
        case .recent: store.recentMeetings
        case .archived: store.archivedMeetings
        case .voiceNotes: active.filter { !$0.isArchived && $0.recordingMode == .voiceNote }
        }

        // Tag filter
        let tagged: [MeetingNote] = if let tag = selectedTagFilter {
            base.filter { $0.tags.contains(tag) }
        } else {
            base
        }

        // Search — use FTS5 index for transcript search instead of linear scan
        let searched: [MeetingNote] = if debouncedSearchText.isEmpty {
            tagged
        } else {
            tagged.filter { meeting in
                meeting.title.localizedCaseInsensitiveContains(debouncedSearchText)
                    || (meeting.summary?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false)
                    || ftsMatchingIDs.contains(meeting.id)
            }
        }

        return sorted(searched)
    }

    private func sorted(_ meetings: [MeetingNote]) -> [MeetingNote] {
        switch sortOrder {
        case .modifiedNewest: meetings.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest: meetings.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAZ: meetings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA: meetings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .createdNewest: meetings.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: meetings.sorted { $0.createdAt < $1.createdAt }
        case .longest: meetings.sorted { $0.duration > $1.duration }
        case .shortest: meetings.sorted { $0.duration < $1.duration }
        }
    }

    // MARK: - Body

    var body: some View {
        listView
            .searchable(text: $searchText, prompt: "Search meetings")
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Filter
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

                        // Sort
                        Section("Sort By") {
                            ForEach(MeetingSortOrder.allCases, id: \.rawValue) { order in
                                Button {
                                    sortOrder = order
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

                        // Selected meeting actions
                        if let meeting = selectedMeeting {
                            Divider()
                            Section {
                                Button {
                                    store.togglePin(id: meeting.id)
                                } label: {
                                    Label(
                                        meeting.isPinned ? "Unpin" : "Pin",
                                        systemImage: meeting.isPinned ? "pin.slash" : "pin"
                                    )
                                }
                                Button {
                                    renameText = meeting.title
                                    renamingMeetingID = meeting.id
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    store.toggleArchive(id: meeting.id)
                                } label: {
                                    Label(
                                        meeting.isArchived ? "Unarchive" : "Archive",
                                        systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
                                    )
                                }
                                Divider()
                                Button(role: .destructive) {
                                    store.trashMeeting(id: meeting.id)
                                } label: {
                                    Label("Move to Trash", systemImage: "trash")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Filter and Sort Options")
                    .accessibilityHint("Opens menu to filter, sort, and manage meetings")
                    .help("Filter, Sort & View Options")
                }
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
                hasAutoSelected = false
                autoSelectFirst()
                calendarManager.refreshUpcomingEvents()
            }
            .onChange(of: store.activeMeetings.count) { _, _ in
                hasAutoSelected = false
                autoSelectFirst()
            }
            .onChange(of: selectedItem) { _, newValue in
                // If selection is cleared, auto-select again
                if newValue == nil {
                    hasAutoSelected = false
                    DispatchQueue.main.async {
                        autoSelectFirst()
                    }
                }
            }
    }

    // MARK: - Auto-select First

    private func autoSelectFirst() {
        guard !hasAutoSelected, selectedItem == nil else { return }

        // If no meetings exist, create one
        if store.activeMeetings.isEmpty {
            let newMeeting = store.createMeeting(
                title: "Untitled Meeting",
                mode: .inPerson,
                template: .general
            )
            selectedItem = .meeting(newMeeting.id)
            hasAutoSelected = true
            return
        }

        // Otherwise select the first meeting
        if let first = filteredMeetings.first {
            selectedItem = .meeting(first.id)
            hasAutoSelected = true
        }
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: selectedTagFilter == nil) {
                    selectedTagFilter = nil
                }
                ForEach(store.allTags, id: \.self) { tag in
                    FilterChip(label: tag, isSelected: selectedTagFilter == tag) {
                        selectedTagFilter = selectedTagFilter == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Upcoming Event Helpers

    private var hasUpcomingEvents: Bool {
        calendarManager.isEnabled && !calendarManager.upcomingEvents.isEmpty
    }

    private func startMeetingFromEvent(_ event: CalendarEvent) {
        var meeting = store.createMeeting(
            title: event.title,
            mode: .onlineMeeting,
            template: .general
        )
        meeting.calendarEventID = event.id
        meeting.scheduledStartTime = event.startDate
        store.updateMeeting(meeting)
        store.pendingAutoRecord = meeting.id
        selectedItem = .meeting(meeting.id)
    }

    // MARK: - List View

    private var listView: some View {
        List(selection: $selectedItem) {
            // Tag filter chips (inline)
            if !store.allTags.isEmpty {
                Section {
                    tagFilterBar
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            // Upcoming events as suggestions at the top
            if hasUpcomingEvents {
                Section {
                    ForEach(calendarManager.upcomingEvents.prefix(3)) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(event.isHappeningNow ? AppThemeConstants.error : event.isStartingSoon ? AppThemeConstants
                                    .warning : AppThemeConstants.accent.opacity(AppThemeConstants.opacityStrong))
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                    Text("·")
                                    Text("\(event.durationMinutes) min")
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }

                            Spacer(minLength: 0)

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
                            .accessibilityLabel("Record \(event.title)")
                            .accessibilityHint("Starts a new meeting recording for this calendar event")
                            .buttonStyle(.bordered)
                            .tint(event.isHappeningNow ? AppThemeConstants.error : AppThemeConstants.accent)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("Upcoming", systemImage: "calendar")
                }
            }

            // Meeting rows
            Section {
                ForEach(filteredMeetings) { meeting in
                    if renamingMeetingID == meeting.id {
                        renameField(for: meeting)
                            .tag(ContentListItem.meeting(meeting.id))
                    } else {
                        MeetingListRow(meeting: meeting)
                            .tag(ContentListItem.meeting(meeting.id))
                            .accessibilityLabel("\(meeting.title)\(meeting.isPinned ? ", pinned" : "")")
                            .accessibilityHint("Opens this meeting")
                            .contextMenu { meetingContextMenu(for: meeting) }
                    }
                }
            } header: {
                if hasUpcomingEvents {
                    Text("Meetings")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
        .overlay {
            if filteredMeetings.isEmpty, !hasUpcomingEvents {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: emptyIcon
        )
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

    // MARK: - Rename

    private func renameField(for meeting: MeetingNote) -> some View {
        TextField("Title", text: $renameText, onCommit: {
            store.renameMeeting(id: meeting.id, newTitle: renameText)
            renamingMeetingID = nil
        })
        .focused($isRenameFieldFocused)
        .textFieldStyle(.plain)
        .font(.subheadline.weight(.medium))
        .padding(.vertical, 4)
        .onExitCommand {
            renamingMeetingID = nil
        }
        .onAppear {
            renameText = meeting.title
            isRenameFieldFocused = true
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func meetingContextMenu(for meeting: MeetingNote) -> some View {
        Button {
            store.togglePin(id: meeting.id)
        } label: {
            Label(
                meeting.isPinned ? "Unpin" : "Pin",
                systemImage: meeting.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            renameText = meeting.title
            renamingMeetingID = meeting.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            store.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        Divider()
        Button(role: .destructive) {
            store.trashMeeting(id: meeting.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

// MARK: - Meeting List Row

struct MeetingListRow: View {
    let meeting: MeetingNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: meeting.recordingMode.iconName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(meeting.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if meeting.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(AppThemeConstants.pinnedColor)
                }
            }
            HStack(spacing: 6) {
                if meeting.duration > 0 {
                    Text(meeting.formattedDuration)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
