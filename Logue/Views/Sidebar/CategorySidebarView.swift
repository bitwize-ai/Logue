import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    /// `@State` rather than `@ObservedObject`: `DocumentStorage` is `@Observable`.
    @State private var documentStorage = DocumentStorage.shared

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
                        rescanButton
                    }
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

    // MARK: - Rescan

    /// Re-reads `~/Logue` on request.
    ///
    /// Icon only, and shown only when plain markdown storage is on — with the setting off there is no
    /// folder to read, so a button would be a promise the app cannot keep.
    ///
    /// Changes are picked up on their own three ways: the folder watcher, a scan at launch, and a
    /// quiet scan whenever the app becomes active. This is the fallback for what none of those cover
    /// — a watcher that could not start because the folder was on an unmounted drive, or a sync
    /// client that moves files without producing events the watcher sees. Rarely needed, and the only
    /// way to ask without quitting.
    @ViewBuilder
    private var rescanButton: some View {
        if documentStorage.mode.isMarkdown {
            Button {
                Task { await documentStorage.rescan() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    // A full turn per repeat, so the arrows land where they started and the
                    // spin reads as continuous rather than as a rock back and forth.
                    .rotationEffect(.degrees(documentStorage.isScanning ? 360 : 0))
                    .animation(rescanSpin, value: documentStorage.isScanning)
            }
            .disabled(documentStorage.isScanning)
            .help(rescanTooltip)
            .accessibilityLabel("Rescan Documents Folder")
        }
    }

    /// Spins while scanning; eases back to rest when it stops.
    ///
    /// The animation is chosen by the same flag that drives the angle, so stopping does not
    /// inherit `repeatForever` and leave the icon turning after the scan is over.
    private var rescanSpin: Animation {
        documentStorage.isScanning
            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
            : .easeOut(duration: 0.2)
    }

    private var rescanTooltip: String {
        guard let summary = documentStorage.lastScanSummary else {
            return "Check the Logue folder for changes made outside Logue"
        }
        return "Check the Logue folder for changes made outside Logue — last check: \(summary.lowercased())"
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
        Button {
            presentImportPanel()
        } label: {
            Label("Import Files…", systemImage: "square.and.arrow.down")
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

    /// Presents an open panel and imports the chosen files into this space.
    /// Import runs entirely on-device (issue #28) — files are read locally and
    /// become documents; nothing is uploaded anywhere.
    private func presentImportPanel() {
        let panel = NSOpenPanel()
        // Filtered by extension rather than `allowedContentTypes`, which matches by
        // conformance: `.swift`, `.csv`, `.py` and `.sh` all conform to
        // `public.plain-text`, so the panel would enable files the importer then
        // rejects. The delegate is retained by the completion closure below.
        let fileFilter = ImportFileFilter()
        panel.delegate = fileFilter
        panel.allowsMultipleSelection = true
        // A vault is a tree. With this off you could navigate into a folder but never choose one,
        // and `NSOpenPanel` will not multi-select across directories — so migrating a 40-folder
        // vault was 40 rounds of this panel, each landing flat in one space with the hierarchy
        // gone. Choosing the vault itself now imports it whole, subfolders becoming sub-spaces.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Import into \(String(space.name.prefix(60)))"
        panel.message = """
        Choose markdown or text files, or a folder to import a whole vault — \
        its subfolders become spaces.
        """

        // The panel outlives this call, so read `space.id` now rather than through
        // `space` later. `selection` is a Binding to state owned further up the
        // tree, so writing it from the completion handler still lands correctly.
        let spaceID = space.id
        let store = documentStore
        let spaces = spaceStore
        panel.begin { @MainActor response in
            _ = fileFilter // Retain the delegate until the panel is done with it.
            guard response == .OK, !panel.urls.isEmpty else { return }

            // The panel is modeless, so the space can be deleted while it is open.
            // Importing into a deleted space would file the documents under an ID
            // with no sidebar row, reachable only through All Documents.
            guard spaces.space(for: spaceID) != nil else {
                presentAlert(
                    title: "Nothing was imported",
                    message: "The space these files were headed for no longer exists."
                )
                return
            }

            let urls = panel.urls
            Task { @MainActor in
                let outcome = await store.importFiles(at: urls, into: spaceID)

                // Reveal the results without stealing the user's place: reveal the
                // space in the tree, but leave the selection where it is.
                // `DocumentStore+Import` makes the same promise for documents.
                if outcome.imported > 0 {
                    spaces.expandPath(to: spaceID)
                }

                // Always reported, not only when something was skipped. A clean import
                // otherwise showed nothing at all beyond a count badge, which reads as
                // "that did nothing" — and running it again produces a second copy of
                // every note, with no bulk undo.
                //
                // Deferred so the panel has finished dismissing and SwiftUI has
                // committed this turn's state before a modal run loop starts.
                //
                // The name is resolved after the import, not before, so it names where
                // the documents actually landed — `importFiles` makes the same re-check
                // and files at the top level if the space went away mid-read.
                let summary = outcome
                let name = spaces.space(for: spaceID).map { String($0.name.prefix(60)) } ?? "Documents"
                DispatchQueue.main.async { reportOutcome(summary, destination: name) }
            }
        }
    }

    /// Reports what an import did, grouped by reason.
    ///
    /// Listing the first ten filenames was close to useless at the scale this is for: skip 200
    /// of 500 and the user gets ten names and a count, in text they cannot select or scroll.
    /// The causes are almost always systematic — one folder of images, one oversized export —
    /// so counting them by reason says the useful thing in one line each.
    private func reportOutcome(_ outcome: DocumentStore.ImportOutcome, destination: String) {
        let title = outcome.imported > 0
            ? "Imported \(outcome.imported) \(outcome.imported == 1 ? "document" : "documents") into \(destination)"
            : "Nothing was imported"

        var lines: [String] = []
        if !outcome.skipped.isEmpty {
            lines.append("Skipped \(outcome.skipped.count):")
            let byReason = Dictionary(grouping: outcome.skipped, by: \.reason)
            for reason in byReason.keys.sorted() {
                guard let files = byReason[reason] else { continue }
                lines.append(files.count == 1
                    ? "  \(files[0].file) — \(reason)"
                    : "  \(files.count) files — \(reason)")
            }
        }
        presentAlert(title: title, message: lines.joined(separator: "\n"))
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
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

/// Restricts an open panel to the extensions the importer accepts.
///
/// `NSOpenPanel.allowedContentTypes` matches by UTI conformance, and `.swift`,
/// `.csv`, `.py` and `.sh` all conform to `public.plain-text` — so a type-based
/// filter enables files `MarkdownImport` then rejects. Matching the extension
/// directly keeps the panel and the importer agreeing on what is importable.
private final class ImportFileFilter: NSObject, NSOpenSavePanelDelegate {
    func panel(_: Any, shouldEnable url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return true
        }
        return MarkdownImport.allowedExtensions.contains(url.pathExtension.lowercased())
    }
}
