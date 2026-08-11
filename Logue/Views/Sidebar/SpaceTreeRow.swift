import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpaceTreeRow: View {
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

    /// The document or meeting under this space currently being renamed. One at a time, so one
    /// piece of state covers both kinds.
    @State private var renamingChildID: UUID?
    @State private var childRenameText = ""
    @FocusState private var isChildFieldFocused: Bool

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
                            // Steps aside for the "⋯" rather than sitting under it.
                            .opacity(isHovered ? 0 : 1)
                            .animation(.easeInOut(duration: AppThemeConstants.hoverDuration), value: isHovered)
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
            // `isHovered` also swaps the folder icon for the disclosure chevron, and is now driven
            // by the menu rather than by its own `onHover`, so the chevron, the count and the
            // button all move together.
            .sidebarRowMenu(isSelected: selection == .space(space.id), revealed: $isHovered) {
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
                    documentRow(doc)
                }

                // Meetings in this space
                ForEach(meetings) { meeting in
                    meetingRow(meeting)
                }
            }
        }
    }

    // MARK: - Child Rows

    @ViewBuilder
    private func documentRow(_ doc: WritingDocument) -> some View {
        if renamingChildID == doc.id {
            childRenameField { documentStore.renameDocument(id: doc.id, newTitle: childRenameText) }
                .padding(.leading, 12)
        } else {
            Label {
                Text(doc.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "doc.text")
            }
            .tag(SidebarItem.document(doc.id))
            .padding(.leading, 12)
            .sidebarRowMenu(isSelected: selection == .document(doc.id)) {
                documentContextMenu(for: doc)
            }
        }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: MeetingNote) -> some View {
        if renamingChildID == meeting.id {
            childRenameField { meetingStore.renameMeeting(id: meeting.id, newTitle: childRenameText) }
                .padding(.leading, 12)
        } else {
            Label {
                Text(meeting.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: meeting.recordingMode.iconName)
            }
            .tag(SidebarItem.meeting(meeting.id))
            .padding(.leading, 12)
            .sidebarRowMenu(isSelected: selection == .meeting(meeting.id)) {
                meetingContextMenu(for: meeting)
            }
        }
    }

    /// The inline field a document or meeting row turns into while it is being renamed. One field
    /// serves both, the same way one `renamingChildID` does.
    private func childRenameField(commit: @escaping () -> Void) -> some View {
        TextField("Name", text: $childRenameText, onCommit: {
            commit()
            renamingChildID = nil
        })
        .textFieldStyle(.plain)
        .font(.callout)
        .focused($isChildFieldFocused)
        .onExitCommand { renamingChildID = nil }
        .onAppear {
            Task {
                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                isChildFieldFocused = true
            }
        }
    }

    private func beginRenamingChild(id: UUID, currentTitle: String) {
        childRenameText = currentTitle
        renamingChildID = id
    }

    // MARK: - Child Row Menus

    /// Kept in step with the same document's menu in the content pane
    /// (`SpaceContentPane+Cards.documentCardContextMenu`) — the sidebar offering a thinner set of
    /// actions than the grid for the very same document is the whole complaint this fixes.
    @ViewBuilder
    private func documentContextMenu(for doc: WritingDocument) -> some View {
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
        Button {
            beginRenamingChild(id: doc.id, currentTitle: doc.title)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        if !spaceStore.topLevelSpaces.isEmpty || doc.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: doc.spaceID) { newSpaceID in
                    documentStore.moveDocument(id: doc.id, toSpace: newSpaceID)
                }
            }
        }
        Button {
            PDFExportService.export(document: doc)
        } label: {
            Label("Export as PDF", systemImage: "arrow.down.doc")
        }
        Divider()
        Button(role: .destructive) {
            documentStore.deleteDocument(id: doc.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    /// Kept in step with `SpaceContentPane+Cards.meetingCardContextMenu`, for the same reason.
    @ViewBuilder
    private func meetingContextMenu(for meeting: MeetingNote) -> some View {
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
        Button {
            beginRenamingChild(id: meeting.id, currentTitle: meeting.title)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            meetingStore.toggleArchive(id: meeting.id)
        } label: {
            Label(
                meeting.isArchived ? "Unarchive" : "Archive",
                systemImage: meeting.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        if !spaceStore.topLevelSpaces.isEmpty || meeting.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: meeting.spaceID) { newSpaceID in
                    meetingStore.moveMeeting(id: meeting.id, toSpace: newSpaceID)
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            meetingStore.trashMeeting(id: meeting.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
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
        guard !outcome.wasCancelled else {
            presentAlert(title: "Import cancelled", message: "Nothing was imported.")
            return
        }

        let title = outcome.imported > 0
            ? "Imported \(outcome.imported) \(outcome.imported == 1 ? "document" : "documents") into \(destination)"
            : "Nothing was imported"

        var lines: [String] = []
        if let stoppedEarly = outcome.stoppedEarly {
            // Said first, because everything below it describes a partial read. Reporting a
            // truncated walk as though it were the whole folder is the worst version of this.
            lines.append("That folder holds \(stoppedEarly), so only part of it was read.")
            lines.append("")
        }
        if !outcome.skipped.isEmpty {
            lines.append("Skipped \(outcome.skipped.count):")
            let byReason = Dictionary(grouping: outcome.skipped, by: \.reason)
            for reason in byReason.keys.sorted() {
                guard let files = byReason[reason], let first = files.first else { continue }
                // Named while the group is small. Grouping solved the 500-file case but took the
                // names away from the 2-file one, where they were the whole point — and the log
                // line that would identify them is redacted.
                if files.count == 1 {
                    lines.append("  \(first.file) — \(reason)")
                } else if files.count <= Self.namedSkipLimit {
                    lines.append("  \(files.map(\.file).joined(separator: ", ")) — \(reason)")
                } else {
                    lines.append("  \(files.count) files — \(reason)")
                }
            }
        }
        presentAlert(title: title, message: lines.joined(separator: "\n"))
    }

    /// How many skipped files are named individually before switching to a count.
    private static let namedSkipLimit = 5

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
