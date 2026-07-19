import SwiftUI

/// Sidebar with unified space tree for the 2-column Notion-style layout.
/// Shows Overview, Spaces (recursive tree with mixed content), All Documents, All Meetings, Trash, and Settings.
struct CategorySidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(TemplateStore.self) private var templateStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAddingSpace = false
    @State private var newSpaceName = ""
    @State private var renamingSpaceID: UUID?
    @State private var renameSpaceText = ""
    @State private var iconPickerSpaceID: UUID?
    @FocusState private var isNewSpaceFieldFocused: Bool
    @State private var showAllSpaces = false

    private let newSpaceFieldID = "newSpaceField"
    private static let maxCollapsedSpaces = 8

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    // Overview
                    // Accessibility note (macOS 26): do NOT add `.accessibilityAddTraits(.isButton)`
                    // to List selection rows — it replaces the AXStaticText element with a synthetic
                    // AXButton whose title is empty, breaking VoiceOver. Rely on the selection-row
                    // role + AXValue text (which lands from the Label's visible content) instead.
                    Section {
                        Label("Home", systemImage: "house")
                            .tag(SidebarItem.overview)
                            .accessibilityLabel("Home")
                            .accessibilityHint("Shows home dashboard")

                        Label("Ask Logue", systemImage: "sparkles")
                            .tag(SidebarItem.agentChat)
                            .accessibilityLabel("Ask Logue")
                            .accessibilityHint("Opens Logue AI assistant")
                    }

                    // Pinned & Recent
                    Section {
                        Label {
                            HStack {
                                Text("Pinned")
                                Spacer()
                                let pinCount = documentStore.pinnedDocuments.count
                                    + meetingStore.activeMeetings.filter(\.isPinned).count
                                if pinCount > 0 {
                                    Text("\(pinCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } icon: {
                            Image(systemName: "pin")
                        }
                        .tag(SidebarItem.pinned)
                        .accessibilityLabel(pinnedAccessibilityLabel)

                        Label("Recent", systemImage: "clock")
                            .tag(SidebarItem.recent)
                            .accessibilityLabel("Recent")
                    }

                    // Smart Views
                    Section("Library") {
                        Label {
                            HStack {
                                Text("All Documents")
                                Spacer()
                                Text("\(documentStore.activeDocuments.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                        .tag(SidebarItem.allDocuments)
                        .accessibilityLabel("All Documents, \(documentStore.activeDocuments.count) items")

                        Label {
                            HStack {
                                Text("All Meetings")
                                Spacer()
                                Text("\(meetingStore.activeMeetings.filter { !$0.isArchived }.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "waveform")
                        }
                        .tag(SidebarItem.allMeetings)
                        .accessibilityLabel("All Meetings, \(meetingStore.activeMeetings.filter { !$0.isArchived }.count) items")

                        Label {
                            HStack {
                                Text("Action Items")
                                Spacer()
                                let pendingCount = pendingActionItemCount
                                if pendingCount > 0 {
                                    Text("\(pendingCount)")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            hasOverdueItems
                                                ? AnyShapeStyle(AppThemeConstants.error)
                                                : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                                        )
                                }
                            }
                        } icon: {
                            Image(systemName: "checklist")
                        }
                        .tag(SidebarItem.actionItems)
                        .accessibilityLabel(actionItemsAccessibilityLabel)
                        .accessibilityHint("View all action items across meetings")

                        Label {
                            HStack {
                                Text("Templates")
                                Spacer()
                                Text("\(templateStore.templates.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                        .tag(SidebarItem.templates)
                        .accessibilityLabel("Templates, \(templateStore.templates.count) items")
                        .accessibilityHint("Browse document templates")
                    }

                    // Phase H: AI Detector moved into the document Verify
                    // panel. Diagrammer + Slide Studio are now agent tools
                    // (`render_diagram`, `generate_slides`). The whole
                    // Productivity section is gone — chat is the entry
                    // point for those capabilities.

                    // Spaces (limited to first N when collapsed)
                    Section("Spaces") {
                        ForEach(visibleSpaces) { space in
                            SpaceTreeRow(
                                space: space, selection: $selection,
                                renamingSpaceID: $renamingSpaceID,
                                renameSpaceText: $renameSpaceText,
                                iconPickerSpaceID: $iconPickerSpaceID
                            )
                        }

                        if shouldCollapseSpaces {
                            Button {
                                withAnimation { showAllSpaces = true }
                            } label: {
                                Label(
                                    "Show \(spaceStore.topLevelSpaces.count - Self.maxCollapsedSpaces) more…",
                                    systemImage: "chevron.down"
                                )
                                .font(.callout).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if isAddingSpace {
                            newSpaceField { isAddingSpace = false }.id(newSpaceFieldID)
                        }

                        Button {
                            newSpaceName = ""
                            isAddingSpace = true
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                withAnimation { proxy.scrollTo(newSpaceFieldID, anchor: .bottom) }
                                isNewSpaceFieldFocused = true
                            }
                        } label: {
                            Label("New Space", systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Space")
                        .accessibilityHint("Creates a new space for organizing items")
                    }
                }
                .listStyle(.sidebar)
                .tint(AppThemeConstants.accent)
                .background(AppThemeConstants.chromeBackground)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newSpaceName = ""
                            isAddingSpace = true
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                withAnimation { proxy.scrollTo(newSpaceFieldID, anchor: .bottom) }
                                isNewSpaceFieldFocused = true
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .help("New Space")
                        .accessibilityLabel("New Space")
                    }
                }
            } // ScrollViewReader

            Divider()

            // Pinned bottom — Trash & Settings always visible
            pinnedBottomBar
        }
    }

    // MARK: - Action Item Counts

    private var pendingActionItemCount: Int {
        meetingStore.activeMeetings
            .filter { !$0.isArchived }
            .reduce(0) { $0 + $1.actionItems.filter { !$0.isCompleted }.count }
    }

    private var hasOverdueItems: Bool {
        let now = Date()
        for meeting in meetingStore.activeMeetings where !meeting.isArchived {
            for item in meeting.actionItems where !item.isCompleted {
                if let due = item.dueDate, due < now {
                    return true
                }
            }
        }
        return false
    }

    private var pinnedAccessibilityLabel: String {
        let count = documentStore.pinnedDocuments.count + meetingStore.activeMeetings.filter(\.isPinned).count
        return count > 0 ? "Pinned, \(count) items" : "Pinned"
    }

    private var actionItemsAccessibilityLabel: String {
        var label = "Action Items"
        if pendingActionItemCount > 0 {
            label += ", \(pendingActionItemCount) pending"
        }
        if hasOverdueItems {
            label += ", some overdue"
        }
        return label
    }

    // MARK: - Spaces Helpers

    private var shouldCollapseSpaces: Bool {
        spaceStore.topLevelSpaces.count > Self.maxCollapsedSpaces && !showAllSpaces
    }

    private var visibleSpaces: [Space] {
        shouldCollapseSpaces
            ? Array(spaceStore.topLevelSpaces.prefix(Self.maxCollapsedSpaces))
            : spaceStore.topLevelSpaces
    }

    // MARK: - Pinned Bottom Bar (Trash + Settings)

    private var pinnedBottomBar: some View {
        VStack(spacing: 0) {
            // Trash row — tappable, highlights when selected
            Button {
                selection = .trash
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .foregroundStyle(selection == .trash ? AppThemeConstants.accent : .secondary)
                        .frame(width: 20)
                    Text("Trash")
                    Spacer()
                    let trashCount = documentStore.trashedDocuments.count + meetingStore.trashedMeetings.count
                    if trashCount > 0 {
                        Text("\(trashCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    selection == .trash
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trash")

            // Settings row
            Button {
                openSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Settings")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppThemeConstants.chromeBackground)
    }

    // MARK: - New Space Field

    private func newSpaceField(onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Space name", text: $newSpaceName, onCommit: {
                let trimmed = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let space = spaceStore.createSpace(name: trimmed) {
                        selection = .space(space.id)
                    }
                }
                isNewSpaceFieldFocused = false
                onDismiss()
            })
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($isNewSpaceFieldFocused)
            .onExitCommand {
                isNewSpaceFieldFocused = false
                onDismiss()
            }
        }
    }
}

// MARK: - SpaceTreeRow (Recursive View Struct — no AnyView)

/// A concrete View struct for rendering a space in the sidebar tree.
/// References itself recursively via ForEach for child spaces.
/// This avoids AnyView type erasure, which breaks List selection highlights.
private struct SpaceTreeRow: View {
    let space: Space
    @Binding var selection: SidebarItem?
    @Binding var renamingSpaceID: UUID?
    @Binding var renameSpaceText: String
    @Binding var iconPickerSpaceID: UUID?

    @Environment(SpaceStore.self) private var spaceStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore

    @FocusState private var isFieldFocused: Bool
    @State private var isHovered = false

    var body: some View {
        if renamingSpaceID == space.id {
            renameField
        } else {
            disclosureContent
        }
    }

    // MARK: - Rename Field

    private var renameField: some View {
        TextField("Space name", text: $renameSpaceText, onCommit: {
            spaceStore.renameSpace(id: space.id, newName: renameSpaceText)
            isFieldFocused = false
            renamingSpaceID = nil
        })
        .textFieldStyle(.plain)
        .font(.callout)
        .focused($isFieldFocused)
        .onExitCommand {
            isFieldFocused = false
            renamingSpaceID = nil
        }
        .onAppear {
            renameSpaceText = space.name
            Task {
                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                isFieldFocused = true
            }
        }
    }

    // MARK: - Disclosure Content

    private var disclosureContent: some View {
        let childSpaces = spaceStore.children(of: space.id)
        let docs = documentStore.documents(inSpace: space.id)
        let meetings = meetingStore.meetings(inSpace: space.id)
        let totalCount = docs.count + meetings.count

        return Group {
            // Space row — icon swaps to chevron on hover (Notion-style)
            Label {
                HStack {
                    Text(space.name)
                    Spacer()
                    if totalCount > 0 {
                        Text("\(totalCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                ZStack {
                    Image(systemName: space.icon ?? "folder")
                        .opacity(isHovered ? 0 : 1)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            spaceStore.toggleExpanded(id: space.id)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(space.isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: space.isExpanded)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .tag(SidebarItem.space(space.id))
            .onHover { isHovered = $0 }
            .contextMenu {
                spaceContextMenu
            }
            .accessibilityLabel("\(space.name) space, \(totalCount) items")
            .popover(isPresented: Binding(
                get: { iconPickerSpaceID == space.id },
                set: {
                    if !$0 {
                        iconPickerSpaceID = nil
                    }
                }
            ), arrowEdge: .trailing) {
                SpaceIconPicker(currentIcon: space.icon) { newIcon in
                    spaceStore.setSpaceIcon(id: space.id, icon: newIcon)
                    iconPickerSpaceID = nil
                }
            }
            .dropDestination(for: WorkspaceDragItem.self) { items, _ in
                handleDrop(items)
            }

            // Expanded children — fade in/out
            if space.isExpanded {
                // Child spaces (recursive)
                ForEach(childSpaces) { child in
                    SpaceTreeRow(
                        space: child,
                        selection: $selection,
                        renamingSpaceID: $renamingSpaceID,
                        renameSpaceText: $renameSpaceText,
                        iconPickerSpaceID: $iconPickerSpaceID
                    )
                    .padding(.leading, 12)
                }

                // Documents in this space
                ForEach(docs) { doc in
                    Label {
                        Text(doc.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                    .tag(SidebarItem.document(doc.id))
                    .padding(.leading, 12)
                    .contextMenu {
                        Button {
                            selection = .document(doc.id)
                        } label: {
                            Label("Open", systemImage: "doc.text")
                        }
                        Button {
                            documentStore.togglePin(id: doc.id)
                        } label: {
                            Label(
                                doc.isPinned ? "Unpin" : "Pin",
                                systemImage: doc.isPinned ? "pin.slash" : "pin"
                            )
                        }
                        Divider()
                        Button(role: .destructive) {
                            documentStore.deleteDocument(id: doc.id)
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                }

                // Meetings in this space
                ForEach(meetings) { meeting in
                    Label {
                        Text(meeting.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: meeting.recordingMode.iconName)
                    }
                    .tag(SidebarItem.meeting(meeting.id))
                    .padding(.leading, 12)
                    .contextMenu {
                        Button {
                            selection = .meeting(meeting.id)
                        } label: {
                            Label("Open", systemImage: meeting.recordingMode.iconName)
                        }
                        Button {
                            meetingStore.togglePin(id: meeting.id)
                        } label: {
                            Label(
                                meeting.isPinned ? "Unpin" : "Pin",
                                systemImage: meeting.isPinned ? "pin.slash" : "pin"
                            )
                        }
                        Divider()
                        Button(role: .destructive) {
                            meetingStore.toggleArchive(id: meeting.id)
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Space Context Menu

    @ViewBuilder
    private var spaceContextMenu: some View {
        Button {
            iconPickerSpaceID = space.id
        } label: {
            Label("Change Icon", systemImage: "star.square.on.square")
        }
        Button {
            renameSpaceText = space.name
            renamingSpaceID = space.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button {
            // Expand parent so the child is visible, create with temp name,
            // then immediately trigger rename so the user can name it.
            if !space.isExpanded {
                spaceStore.toggleExpanded(id: space.id)
            }
            if let child = spaceStore.createSpace(name: "New Space", parentID: space.id) {
                selection = .space(child.id)
                renameSpaceText = ""
                renamingSpaceID = child.id
            }
        } label: {
            Label("New Sub-Space", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            if selection == .space(space.id) {
                selection = .overview
            }
            spaceStore.deleteSpace(id: space.id)
        } label: {
            Label("Delete Space", systemImage: "trash")
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ items: [WorkspaceDragItem]) -> Bool {
        var handled = false
        for item in items {
            switch item.type {
            case .document:
                documentStore.moveDocument(id: item.id, toSpace: space.id)
                handled = true
            case .meeting:
                meetingStore.moveMeeting(id: item.id, toSpace: space.id)
                handled = true
            case .space:
                guard item.id != space.id else { continue }
                spaceStore.moveSpace(id: item.id, toParent: space.id)
                handled = true
            }
        }
        return handled
    }
}
