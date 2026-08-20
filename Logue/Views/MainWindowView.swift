import SwiftUI

// MARK: - Navigation Enums

/// Sidebar selection in the 2-column layout.
enum SidebarItem: Hashable {
    /// The merged landing surface: prompt bar, dashboard cards, and the chat thread
    /// once one starts. Replaces the separate `overview` and `agentChat` items.
    case home
    case pinned
    case recent
    case allDocuments
    case allMeetings
    case tasks
    // Action Items and Templates used to live here. They are now panels of All Meetings and
    // All Documents — see `LibraryPanel` — because each is a lens on a library rather than a
    // sibling of it. `SidebarSelectionMigration` maps the old persisted values.
    case space(UUID)
    case document(UUID)
    case meeting(UUID)
    case trash
}

/// Legacy enums kept for backward compatibility with unused pane views.
enum SidebarCategory: String, Hashable {
    case overview, documents, meetings, trash
}

enum ContentListItem: Hashable {
    case document(UUID)
    case meeting(UUID)
}

// MARK: - MainWindowView

/// Root view: Notion-style 2-column layout.
/// - Column 1 (sidebar): Category navigation with space trees
/// - Column 2 (detail): Content area — list views or editor workspace
struct MainWindowView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.colorScheme) private var colorScheme
    // Extension-visible: +Navigation
    @State var store = DocumentStore.shared
    // Extension-visible: +Navigation
    @State var meetingStore = MeetingStore.shared
    @State private var spaceStore = SpaceStore.shared
    @State private var insightsProvider = InsightsStatsProvider(meetingStore: .shared, documentStore: .shared)
    @State private var templateStore = TemplateStore.shared

    // Extension-visible: +Navigation
    /// Default landing surface is Home — the merged prompt-and-dashboard screen.
    /// Persists the last-selected non-document surface so a user who navigated to a
    /// meeting detail and quit returns to the meeting on relaunch; a fresh install,
    /// or one without a stored value, lands on Home.
    @State var sidebarSelection: SidebarItem? = Self.loadLastSidebarSelection() ?? .home
    // Extension-visible: +Navigation
    /// When true, the content area shows the editor/workspace instead of the list.
    @State var isEditing = false

    /// U10: Version-counter suppression to prevent onChange feedback loops.
    /// When sidebar drives a store change, store onChange should ignore it (and vice versa).
    /// Uses monotonic counters instead of booleans to avoid race conditions from rapid selections.
    @State private var sidebarChangeVersion: Int = 0
    // Extension-visible: +Navigation
    @State var storeChangeVersion: Int = 0
    @State private var lastSeenSidebarVersion: Int = 0
    @State private var lastSeenStoreVersion: Int = 0

    @State private var showCommandPalette = false
    @State private var showQuickOpen = false

    // Extension-visible: +LibraryPanels
    /// The library panels, collapsed unless the last session ended inside one.
    ///
    /// Both read the same stored value at init rather than one deriving from the other,
    /// because `@State` initialisers cannot see each other.
    @State var meetingsPanelCollapsed = Self.loadRestoredPanel() != .actionItems
    // Extension-visible: +LibraryPanels
    @State var documentsPanelCollapsed = Self.loadRestoredPanel() != .templates
    /// Panel widths, kept here so closing and reopening a panel returns it to the width the
    /// user dragged it to.
    @State private var meetingsPanelWidth = LibraryPanelContainer<EmptyView>.defaultWidth
    @State private var documentsPanelWidth = LibraryPanelContainer<EmptyView>.defaultWidth
    // Extension-visible: +LibraryPanels
    @State var taskStore = TaskStore.shared

    /// Which panes are shown, driven by ⌘1 / ⌘2 / ⌘3 and persisted across launches.
    ///
    /// Stored as the raw string so `@AppStorage` can hold it directly; `layoutMode` below is
    /// the typed view of it, and every layout decision reads `showsList` / `showsInspector`
    /// from `EditorLayoutMode` rather than re-deriving what each mode means.
    @AppStorage(AppConstants.UserDefaultsKeys.editorLayoutMode) private var layoutModeRaw =
        EditorLayoutMode.allPanels.rawValue

    private var layoutMode: EditorLayoutMode {
        EditorLayoutMode(rawValue: layoutModeRaw) ?? .allPanels
    }

    // Extension-visible: +Navigation
    /// Remembers the sidebar context when entering editing mode (since sidebarSelection is nilled out).
    @State var editingSourceSelection: SidebarItem?

    /// Bridge between `EditorLayoutMode` and the split view's own column visibility.
    ///
    /// What a report back from the split view means is decided by
    /// `EditorLayoutMode.modeAfterVisibilityReport(listIsVisible:current:)` rather than here,
    /// because that rule is subtle enough to be worth a test — see its doc comment for the bugs
    /// that made it so.
    ///
    /// `current` is `EditorLayoutMode.stored`, read fresh from `UserDefaults`, and not
    /// `layoutMode`. That is load-bearing: `@AppStorage` caches, so within the update that
    /// echoes our own write back, `layoutMode` still reads the mode we just replaced.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { layoutMode.showsList ? .all : .detailOnly },
            set: { newValue in
                let next = EditorLayoutMode.modeAfterVisibilityReport(
                    listIsVisible: newValue != .detailOnly,
                    current: EditorLayoutMode.stored
                )
                guard let next else { return }
                layoutModeRaw = next.rawValue
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            CategorySidebarView(selection: $sidebarSelection)
                // A static ceiling, deliberately: measuring the window to bound this column
                // means writing state during the split view's first layout, and this split
                // view persists any `.detailOnly` it reports — see `columnVisibility`. The
                // window-relative rule would only bind under 960pt anyway.
                .navigationSplitViewColumnWidth(
                    min: SidebarWidthLimit.categorySidebar.minimum, ideal: 240,
                    max: SidebarWidthLimit.categorySidebar.ceiling
                )
        } detail: {
            contentArea
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .sidebarToggle)
        .environment(store)
        .environment(meetingStore)
        .environment(spaceStore)
        .environment(templateStore)
        .environment(modelManager)
        .environment(insightsProvider)
        // Chat-first shortcut handlers.
        // ⌘L creates a new chat and surfaces Home. Because a conversation with no
        // messages *is* the landing state, this doubles as "go Home" — which is the
        // right meaning for it now that the two surfaces are one.
        .onReceive(NotificationCenter.default.publisher(for: .chatNewConversation)) { _ in
            let conv = AgentConversationStore.shared.createConversation()
            AgentConversationStore.shared.selectedConversationID = conv.id
            sidebarSelection = .home
            isEditing = false
        }
        // ⌘⇧L surfaces Home and focuses the input — does NOT create a new
        // conversation, so users can append a message to the active one.
        .onReceive(NotificationCenter.default.publisher(for: .chatFocusInput)) { _ in
            sidebarSelection = .home
            isEditing = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .openQuickOpenPalette)) { _ in
            toggleQuickOpen()
        }
        // When sidebar selection changes, handle navigation
        .onChange(of: sidebarSelection) { _, newValue in
            // Skip if this change was driven by a store onChange (content pane click)
            guard storeChangeVersion == lastSeenStoreVersion else {
                lastSeenStoreVersion = storeChangeVersion
                return
            }
            sidebarChangeVersion += 1

            switch newValue {
            case let .document(id):
                if let doc = store.documents.first(where: { $0.id == id }),
                   let spaceID = doc.spaceID
                {
                    editingSourceSelection = .space(spaceID)
                }
                withAnimation(.easeOut(duration: 0.08)) {
                    isEditing = true
                    store.selectedDocumentID = id
                    meetingStore.selectedMeetingID = nil
                }
            case let .meeting(id):
                if let idx = meetingStore.meetingIndex(for: id),
                   let spaceID = meetingStore.meetings[idx].spaceID
                {
                    editingSourceSelection = .space(spaceID)
                }
                withAnimation(.easeOut(duration: 0.08)) {
                    isEditing = true
                    meetingStore.selectedMeetingID = id
                    store.selectedDocumentID = nil
                }
            default:
                withAnimation(.easeOut(duration: 0.08)) {
                    isEditing = false
                    store.selectedDocumentID = nil
                    meetingStore.selectedMeetingID = nil
                }
                if let newValue {
                    let tabName = switch newValue {
                    case .home: "home"
                    case .pinned: "favorites"
                    case .recent: "recent"
                    case .allDocuments: "documents"
                    case .allMeetings: "meetings"
                    case .tasks: "tasks"
                    case .space: "space"
                    case .document: "document"
                    case .meeting: "meeting"
                    case .trash: "trash"
                    }
                }
            }
            // Mark sidebar version as seen immediately so subsequent store-driven
            // selection changes (e.g. "New Document" button) are not suppressed.
            lastSeenSidebarVersion = sidebarChangeVersion
            // Persist the last "stable" surface so we land back here on relaunch.
            // Skip persistence for in-flight document/meeting selections — those
            // are restored separately via store.selectedDocumentID, and we don't
            // want a deleted document leaving the user on a blank pane.
            Self.persistSidebarSelection(newValue)
        }
        // When a document is selected from content pane (not sidebar), enter editing mode
        .onChange(of: store.selectedDocumentID) { old, new in
            // Skip if this change was driven by a sidebar click (same runloop)
            guard sidebarChangeVersion == lastSeenSidebarVersion else { return }
            if let new, new != old {
                // Skip if sidebar already shows this document (echo from sidebar's own selection)
                guard sidebarSelection != .document(new) else { return }
                if let currentSidebar = sidebarSelection {
                    editingSourceSelection = currentSidebar
                }
                storeChangeVersion += 1
                sidebarSelection = .document(new)
                withAnimation(.easeOut(duration: 0.08)) {
                    isEditing = true
                }
                meetingStore.selectedMeetingID = nil
            }
        }
        // When a meeting is selected from content pane (not sidebar), enter editing mode
        .onChange(of: meetingStore.selectedMeetingID) { old, new in
            // Skip if this change was driven by a sidebar click (same runloop)
            guard sidebarChangeVersion == lastSeenSidebarVersion else { return }
            if let new, new != old {
                // Skip if sidebar already shows this meeting (echo from sidebar's own selection)
                guard sidebarSelection != .meeting(new) else { return }
                if let currentSidebar = sidebarSelection {
                    editingSourceSelection = currentSidebar
                }
                storeChangeVersion += 1
                sidebarSelection = .meeting(new)
                withAnimation(.easeOut(duration: 0.08)) {
                    isEditing = true
                }
                store.selectedDocumentID = nil
            }
        }
        // Command Palette (Cmd+K)
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    VStack {
                        CommandPaletteView(
                            isPresented: $showCommandPalette,
                            commands: buildCommands()
                        )
                        .padding(.top, 80)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        // Quick Open (⌘P / ⌘O).
        //
        // A sheet rather than an `.overlay` like the command palette above, because an overlay
        // on this `NavigationSplitView` does not draw: clicking the menu item posted the
        // notification and flipped the state, and nothing appeared. The same is true of the
        // ⌘K palette, which is why it does not open either — a separate problem, left alone
        // here. The issue for this work named a sheet as an acceptable shape, and a sheet is
        // also the modality quick-open wants: it takes focus, and Esc dismisses it.
        .sheet(isPresented: $showQuickOpen) {
            QuickOpenPaletteView(isPresented: $showQuickOpen)
        }
        .onKeyPress(keys: [KeyEquivalent("k")], phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            showCommandPalette.toggle()
            return .handled
        }
        // ⌘= is the alias for Zoom In. The View menu binds ⌘+, which on any layout where `+`
        // needs Shift is a chord the menu never matches — so the unshifted key in the same
        // physical position is handled here instead. It cannot be a second menu item: see
        // the comment on the zoom group in `LogueApp`.
        //
        // The exact `==` is load-bearing, not a stylistic difference from the `.contains` used
        // for ⌘K below. On a US layout ⌘⇧= *is* ⌘+, which the View menu already binds; with
        // `.contains(.command)` that one chord would fire the menu item and this handler both,
        // and zoom would jump two steps.
        .onKeyPress(keys: [KeyEquivalent("=")], phases: .down) { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            EditorZoom.mutatePersisted { $0.zoomIn() }
            return .handled
        }
        // ⌘O, the secondary binding. ⌘P arrives as a notification from the File menu instead,
        // so it fires even when the editor's text view holds focus — a main-menu key equivalent
        // is handled before the key event reaches any view.
        .onKeyPress(keys: [KeyEquivalent("o")], phases: .down) { keyPress in
            // Plain ⌘O only: without the check, ⇧⌘O would open quick-open too.
            guard keyPress.modifiers == .command else { return .ignored }
            toggleQuickOpen()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("f")], phases: .down) { keyPress in
            // ⇧⌘F — Enter Focus Mode (only meaningful when editing a document).
            guard keyPress.modifiers.contains([.command, .shift]),
                  isEditing,
                  store.selectedDocumentID != nil
            else { return .ignored }
            focusState.toggle()
            return .handled
        }
    }

    /// Shows or dismisses quick-open, closing the command palette first so the two are never
    /// stacked on top of each other.
    private func toggleQuickOpen() {
        showCommandPalette = false
        showQuickOpen.toggle()
    }

    // MARK: - Content Area

    @State private var focusState = FocusModeState.shared

    @ViewBuilder
    private var contentArea: some View {
        if isEditing, let docID = store.selectedDocumentID {
            VStack(spacing: 0) {
                if !focusState.isActive {
                    breadcrumbBar
                    Divider()
                }
                DocumentWorkspaceView()
            }
            .id(docID)
        } else if isEditing, let meetingID = meetingStore.selectedMeetingID {
            VStack(spacing: 0) {
                breadcrumbBar
                Divider()
                MeetingWorkspaceView()
            }
            .id(meetingID)
        } else {
            listContentView
        }
    }

    @ViewBuilder
    private var listContentView: some View {
        switch sidebarSelection {
        case .home, nil:
            AgentChatView(onOpenSpace: { sidebarSelection = .space($0) })
        case .pinned:
            PinnedContentPane()
        case .recent:
            RecentContentPane()
        case .allDocuments:
            DocumentListContentView(spaceID: nil) {
                LibraryPanelContainer(
                    isCollapsed: $documentsPanelCollapsed,
                    width: $documentsPanelWidth
                ) {
                    TemplateListPanel()
                }
            }
            .libraryPanelToggle(isCollapsed: $documentsPanelCollapsed, panel: .templates)
        case .allMeetings:
            MeetingListContentView(spaceID: nil) {
                LibraryPanelContainer(
                    isCollapsed: $meetingsPanelCollapsed,
                    width: $meetingsPanelWidth
                ) {
                    ActionItemInboxPanel()
                }
            }
            .libraryPanelToggle(
                isCollapsed: $meetingsPanelCollapsed,
                panel: .actionItems,
                badgeCount: actionItemInboxCount
            )
        case .tasks:
            TaskListView()
        case let .space(id):
            SpaceContentPane(spaceID: id, sidebarSelection: $sidebarSelection)
        case .trash:
            TrashListPane()
        case .document, .meeting:
            // Handled by isEditing check in contentArea
            EmptyView()
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            // Full breadcrumb trail
            ForEach(Array(breadcrumbSegments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                if segment.isClickable {
                    Button {
                        handleBreadcrumbClick(segment)
                    } label: {
                        Text(segment.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppThemeConstants.accent)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(segment.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppThemeConstants.surfaceBackground)
    }

    // Extension-visible: +Navigation
    /// A single segment in the breadcrumb trail.
    struct BreadcrumbSegment: Identifiable {
        var id: String {
            if let item = sidebarItem {
                return "\(item)"
            }
            return label
        }

        let label: String
        let sidebarItem: SidebarItem?
        var isClickable: Bool {
            sidebarItem != nil
        }
    }

    /// Builds the full breadcrumb path: [full space path from root...] > [item title]
    private var breadcrumbSegments: [BreadcrumbSegment] {
        var segments: [BreadcrumbSegment] = []

        let source = editingSourceSelection ?? .home

        // 1. Get the item's space and show the full hierarchy from root
        let itemSpaceID: UUID? = {
            if let doc = store.selectedDocument {
                return doc.spaceID
            }
            if let meeting = meetingStore.selectedMeeting {
                return meeting.spaceID
            }
            return nil
        }()

        if let spaceID = itemSpaceID {
            let spacePath = spaceStore.path(to: spaceID)

            if spacePath.isEmpty {
                // No space path — show the source label as fallback
                segments.append(BreadcrumbSegment(label: breadcrumbSourceLabel, sidebarItem: source))
            } else {
                // Full space path from root to the item's space
                for space in spacePath {
                    segments.append(BreadcrumbSegment(label: space.name, sidebarItem: .space(space.id)))
                }
            }
        } else {
            // Item not in a space — show source label (Home, Favorites, All Documents, etc.)
            segments.append(BreadcrumbSegment(label: breadcrumbSourceLabel, sidebarItem: source))
        }

        // 2. Current item title (not clickable — already viewing it)
        if let doc = store.selectedDocument {
            segments.append(BreadcrumbSegment(label: doc.title, sidebarItem: nil))
        } else if let meeting = meetingStore.selectedMeeting {
            segments.append(BreadcrumbSegment(label: meeting.title, sidebarItem: nil))
        }

        return segments
    }

    private var breadcrumbSourceLabel: String {
        let source = editingSourceSelection ?? .home
        switch source {
        case .home: return "Home"
        case .pinned: return "Pinned"
        case .recent: return "Recent"
        case .allDocuments: return "All Documents"
        case .allMeetings: return "All Meetings"
        case .tasks: return "Tasks"
        case let .space(id): return spaceStore.space(for: id)?.name ?? "Space"
        case .trash: return "Trash"
        case .document, .meeting: return "Back"
        }
    }

    // MARK: - Command Palette Commands

    private func buildCommands() -> [CommandItem] {
        var commands: [CommandItem] = []
        commands.append(contentsOf: navigationCommands())
        commands.append(contentsOf: createCommands())
        if isEditing, store.selectedDocumentID != nil {
            commands.append(focusModeCommand())
        }
        commands.append(contentsOf: recentDocumentCommands())
        commands.append(contentsOf: recentMeetingCommands())
        return commands
    }

    private func navigationCommands() -> [CommandItem] {
        let entries: [(String, String, SidebarItem)] = [
            ("Home", "house", .home),
            ("Pinned", "pin", .pinned),
            ("Recent", "clock", .recent),
            ("All Documents", "doc.text", .allDocuments),
            ("All Meetings", "mic", .allMeetings),
            ("Tasks", "checkmark.circle", .tasks),
            ("Trash", "trash", .trash),
        ]
        let surfaces = entries.map { title, icon, destination in
            CommandItem(title, icon: icon, category: .navigation) {
                goBack()
                sidebarSelection = destination
            }
        }
        // The two that became panels keep their entries. With no sidebar row left, the
        // palette is how they are found — dropping them here would make the features
        // reachable only by knowing which surface hides them.
        return surfaces + LibraryPanel.allCases.map { panel in
            CommandItem(panel.title, icon: panel.symbolName, category: .navigation) {
                goBack()
                sidebarSelection = panel.host
                open(panel)
            }
        }
    }

    private func createCommands() -> [CommandItem] {
        [
            CommandItem("New Document", icon: "plus.square", category: .create, subtitle: "Cmd+N") {
                sidebarSelection = .allDocuments
                let doc = store.createDocument()
                store.selectedDocumentID = doc.id
            },
        ]
    }

    private func focusModeCommand() -> CommandItem {
        let focusLabel = focusState.isActive ? "Exit Focus Mode" : "Enter Focus Mode"
        let focusIcon = focusState.isActive ? "xmark.circle" : "rectangle.center.inset.filled"
        return CommandItem(focusLabel, icon: focusIcon, category: .navigation, subtitle: "⇧⌘F") {
            focusState.toggle()
        }
    }

    /// Recent documents shown when the palette has no query. When the user types,
    /// CommandPaletteView runs a live FTS search across all content instead.
    private func recentDocumentCommands() -> [CommandItem] {
        store.activeDocuments
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(5)
            .map { doc in
                CommandItem(
                    doc.title.isEmpty ? "Untitled Document" : doc.title,
                    icon: "doc.text",
                    category: .document,
                    subtitle: "Edited \(doc.modifiedAt.formatted(.relative(presentation: .named)))"
                ) {
                    store.selectedDocumentID = doc.id
                }
            }
    }

    private func recentMeetingCommands() -> [CommandItem] {
        meetingStore.activeMeetings
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(5)
            .map { meeting in
                CommandItem(
                    meeting.title,
                    icon: "waveform",
                    category: .meeting,
                    subtitle: meeting.createdAt.formatted(date: .abbreviated, time: .shortened)
                ) {
                    meetingStore.selectedMeetingID = meeting.id
                }
            }
    }
}
