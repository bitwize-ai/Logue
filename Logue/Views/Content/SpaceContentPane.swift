import SwiftUI

/// Displays the mixed contents of a Space — documents, meetings, and sub-spaces.
struct SpaceContentPane: View {
    let spaceID: UUID
    @Binding var sidebarSelection: SidebarItem?
    // Note: internal (not private) because SpaceContentPane+Cards.swift extension accesses these
    @Environment(DocumentStore.self) var documentStore
    @Environment(MeetingStore.self) var meetingStore
    @Environment(SpaceStore.self) var spaceStore

    @AppStorage("spaceViewMode") var viewModeRaw = ContentViewMode.list.rawValue
    @State var searchText = ""
    @State private var filterType: SpaceFilterType = .all
    @State private var sortOrder: SpaceSortOrder = .modifiedNewest
    @State var renamingSpaceID: UUID?
    @State var renamingDocID: UUID?
    @State var renamingMeetingID: UUID?
    @State var renameText = ""
    @State var iconPickerSpaceID: UUID?
    @State private var showSummaryPopover = false
    @State private var showActionItemsPopover = false
    @State private var showDecisionsPopover = false
    @State private var showStatusUpdatePopover = false
    @State private var aiTracker = SpaceAIGenerationTracker()

    var viewMode: ContentViewMode {
        ContentViewMode(rawValue: viewModeRaw) ?? .list
    }

    var space: Space? {
        spaceStore.space(for: spaceID)
    }

    // MARK: - Items

    var documents: [WritingDocument] {
        documentStore.documents(inSpace: spaceID)
    }

    var meetings: [MeetingNote] {
        meetingStore.meetings(inSpace: spaceID).filter { !$0.isArchived }
    }

    var childSpaces: [Space] {
        spaceStore.children(of: spaceID)
    }

    var allItems: [SpaceItem] {
        var items: [SpaceItem] = []

        items += childSpaces.map { SpaceItem.space($0) }

        if filterType == .all || filterType == .documents {
            items += documents.map { SpaceItem.document($0) }
        }
        if filterType == .all || filterType == .meetings {
            items += meetings.map { SpaceItem.meeting($0) }
        }

        if !searchText.isEmpty {
            let query = searchText
            items = items.filter { item in
                switch item {
                case let .document(doc):
                    doc.title.localizedCaseInsensitiveContains(query)
                        || doc.body.localizedCaseInsensitiveContains(query)
                case let .meeting(meeting):
                    meeting.title.localizedCaseInsensitiveContains(query)
                        || (meeting.summary?.localizedCaseInsensitiveContains(query) ?? false)
                case let .space(space):
                    space.name.localizedCaseInsensitiveContains(query)
                        || (space.summary?.localizedCaseInsensitiveContains(query) ?? false)
                }
            }
        }

        return sorted(items)
    }

    private func sorted(_ items: [SpaceItem]) -> [SpaceItem] {
        items.sorted { lhs, rhs in
            switch sortOrder {
            case .modifiedNewest: lhs.modifiedAt > rhs.modifiedAt
            case .modifiedOldest: lhs.modifiedAt < rhs.modifiedAt
            case .titleAZ: lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .titleZA: lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            case .createdNewest: lhs.createdAt > rhs.createdAt
            case .createdOldest: lhs.createdAt < rhs.createdAt
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let space {
                breadcrumbBar(for: space)
                Divider()
            }

            let items = allItems
            if items.isEmpty {
                emptyState
            } else if viewMode == .grid {
                contentGrid(items)
            } else {
                contentList(items)
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle(space?.name ?? "Space")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search space")
        .toolbar {
            spaceToolbarContent
        }
        .alert("Rename Space", isPresented: Binding(
            get: { renamingSpaceID != nil },
            set: {
                if !$0 {
                    renamingSpaceID = nil
                }
            }
        )) {
            TextField("Space name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingSpaceID = nil }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renamingSpaceID, !trimmed.isEmpty {
                    spaceStore.renameSpace(id: id, newName: trimmed)
                }
                renamingSpaceID = nil
            }
        }
        .alert("Rename Document", isPresented: Binding(
            get: { renamingDocID != nil },
            set: {
                if !$0 {
                    renamingDocID = nil
                }
            }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renamingDocID = nil }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renamingDocID, !trimmed.isEmpty {
                    documentStore.renameDocument(id: id, newTitle: trimmed)
                }
                renamingDocID = nil
            }
        }
        .alert("Rename Meeting", isPresented: Binding(
            get: { renamingMeetingID != nil },
            set: {
                if !$0 {
                    renamingMeetingID = nil
                }
            }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renamingMeetingID = nil }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renamingMeetingID, !trimmed.isEmpty {
                    meetingStore.renameMeeting(id: id, newTitle: trimmed)
                }
                renamingMeetingID = nil
            }
        }
        .popover(isPresented: Binding(
            get: { iconPickerSpaceID != nil },
            set: {
                if !$0 {
                    iconPickerSpaceID = nil
                }
            }
        ), arrowEdge: .trailing) {
            if let pickingID = iconPickerSpaceID {
                SpaceIconPicker(currentIcon: spaceStore.space(for: pickingID)?.icon) { newIcon in
                    spaceStore.setSpaceIcon(id: pickingID, icon: newIcon)
                    iconPickerSpaceID = nil
                }
            }
        }
    }

    private var subtitle: String {
        let dc = documents.count
        let mc = meetings.count
        var parts: [String] = []
        if dc > 0 {
            parts.append("\(dc) doc\(dc == 1 ? "" : "s")")
        }
        if mc > 0 {
            parts.append("\(mc) meeting\(mc == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Breadcrumb

    private func breadcrumbBar(for space: Space) -> some View {
        let path = spaceStore.path(to: space.id)
        return HStack(spacing: 4) {
            ForEach(Array(path.enumerated()), id: \.element.id) { index, ancestor in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if index == path.count - 1 {
                    Text(ancestor.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Button {
                        sidebarSelection = .space(ancestor.id)
                    } label: {
                        Text(ancestor.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var spaceToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            newItemMenu
        }
        ToolbarItemGroup(placement: .primaryAction) {
            aiPopoverButton(
                "Space Summary",
                icon: "text.justify.leading",
                key: "summary",
                isPresented: $showSummaryPopover,
                action: SpaceAIService.summarizeSpace
            )

            aiPopoverButton(
                "Action Items",
                icon: "checklist",
                key: "actionItems",
                isPresented: $showActionItemsPopover,
                action: SpaceAIService.aggregateActionItems
            )

            aiPopoverButton(
                "Decisions",
                icon: "checkmark.seal",
                key: "decisions",
                isPresented: $showDecisionsPopover,
                action: SpaceAIService.extractDecisions
            )

            aiPopoverButton(
                "Status Update",
                icon: "doc.badge.gearshape",
                key: "statusUpdate",
                isPresented: $showStatusUpdatePopover,
                action: SpaceAIService.generateStatusUpdate
            )

            filterSortMenu
        }
    }

    private var filterSortMenu: some View {
        Menu {
            Section("View") {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModeRaw = ContentViewMode.list.rawValue
                    }
                } label: {
                    HStack {
                        Label("List", systemImage: "list.bullet")
                        if viewMode == .list {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModeRaw = ContentViewMode.grid.rawValue
                    }
                } label: {
                    HStack {
                        Label("Grid", systemImage: "square.grid.2x2")
                        if viewMode == .grid {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section("Filter") {
                ForEach(SpaceFilterType.allCases, id: \.self) { type in
                    Button {
                        filterType = type
                    } label: {
                        HStack {
                            Label(type.label, systemImage: type.icon)
                            if filterType == type {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section("Sort By") {
                ForEach(SpaceSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.label)
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
        .help("Options")
    }

    private func aiPopoverButton(
        _ title: String,
        icon: String,
        key: String,
        isPresented: Binding<Bool>,
        action: @escaping (UUID) async throws -> String
    ) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
        }
        .help(title)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            SpaceAIPopover(
                title: title,
                icon: icon,
                insightKey: key,
                spaceID: spaceID,
                action: action,
                onDismiss: { isPresented.wrappedValue = false }
            )
            .environment(spaceStore)
            .environment(documentStore)
            .environment(meetingStore)
            .environment(aiTracker)
        }
    }

    private var newItemMenu: some View {
        Menu {
            Button {
                let doc = documentStore.createDocument(inSpace: spaceID)
                documentStore.selectedDocumentID = doc.id
            } label: {
                Label("New Document", systemImage: "doc.badge.plus")
            }
            Button {
                let meeting = meetingStore.createMeeting(
                    title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                    inSpace: spaceID
                )
                meetingStore.selectedMeetingID = meeting.id
            } label: {
                Label("New Meeting", systemImage: "waveform.badge.plus")
            }
            Divider()
            Button {
                if let sub = spaceStore.createSpace(name: "New Space", parentID: spaceID) {
                    renameText = ""
                    renamingSpaceID = sub.id
                }
            } label: {
                Label("New Sub-Space", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("New Item")
        }
        .help("New item")
    }

    // MARK: - Content List

    func contentList(_ items: [SpaceItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    switch item {
                    case let .space(child):
                        spaceRow(child)
                            .draggable(WorkspaceDragItem(id: child.id, type: .space))
                            .dropDestination(for: WorkspaceDragItem.self) { items, _ in
                                handleDrop(items, intoSpace: child.id)
                            }
                    case let .document(doc):
                        documentRow(doc)
                            .draggable(WorkspaceDragItem(id: doc.id, type: .document))
                    case let .meeting(meeting):
                        meetingRow(meeting)
                            .draggable(WorkspaceDragItem(id: meeting.id, type: .meeting))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Content Grid

    func contentGrid(_ items: [SpaceItem]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)],
                spacing: 16
            ) {
                ForEach(items) { item in
                    switch item {
                    case let .space(child):
                        spaceGridCard(child)
                            .draggable(WorkspaceDragItem(id: child.id, type: .space))
                            .dropDestination(for: WorkspaceDragItem.self) { items, _ in
                                handleDrop(items, intoSpace: child.id)
                            }
                    case let .document(doc):
                        documentGridCard(doc)
                            .draggable(WorkspaceDragItem(id: doc.id, type: .document))
                    case let .meeting(meeting):
                        meetingGridCard(meeting)
                            .draggable(WorkspaceDragItem(id: meeting.id, type: .meeting))
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Empty Space", systemImage: "folder")
        } description: {
            Text("Add documents, meetings, or sub-spaces to organize your work.")
        } actions: {
            HStack(spacing: 12) {
                Button("New Document") {
                    let doc = documentStore.createDocument(inSpace: spaceID)
                    documentStore.selectedDocumentID = doc.id
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)

                Button("New Meeting") {
                    let meeting = meetingStore.createMeeting(
                        title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                        inSpace: spaceID
                    )
                    meetingStore.selectedMeetingID = meeting.id
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
