import SwiftUI

// MARK: - Sort & Filter Options

enum DocSortOrder: String, CaseIterable {
    case modifiedNewest = "Last Modified"
    case modifiedOldest = "Oldest Modified"
    case titleAZ = "Title A–Z"
    case titleZA = "Title Z–A"
    case createdNewest = "Newest Created"
    case createdOldest = "Oldest Created"

    /// The nearest equivalent a saved view can store.
    ///
    /// `SavedViewSort` has no created-at cases, so those fall back to modified in the same
    /// direction rather than silently becoming the default.
    var asSavedViewSort: SavedViewSort {
        switch self {
        case .modifiedNewest, .createdNewest: .recentlyModified
        case .modifiedOldest, .createdOldest: .oldestModified
        case .titleAZ: .titleAscending
        case .titleZA: .titleDescending
        }
    }

    var icon: String {
        switch self {
        case .modifiedNewest, .createdNewest: "arrow.down"
        case .modifiedOldest, .createdOldest: "arrow.up"
        case .titleAZ: "textformat.abc"
        case .titleZA: "textformat.abc"
        }
    }

    var isDateBased: Bool {
        switch self {
        case .modifiedNewest, .modifiedOldest, .createdNewest, .createdOldest: true
        case .titleAZ, .titleZA: false
        }
    }

    var dateKeyPath: KeyPath<WritingDocument, Date>? {
        switch self {
        case .modifiedNewest, .modifiedOldest: \.modifiedAt
        case .createdNewest, .createdOldest: \.createdAt
        default: nil
        }
    }
}

enum DocFilterMode: String, CaseIterable {
    case all = "All Documents"
    case inbox = "Inbox"
    case pinned = "Pinned"
    case recent = "Recent"

    var icon: String {
        switch self {
        case .all: "doc.text"
        case .inbox: "tray"
        case .pinned: "pin"
        case .recent: "clock"
        }
    }
}

// MARK: - DocumentListPane

/// Column 2 content when Documents category is selected.
/// Shows search, filter/sort/view menus, and a selectable document list or gallery.
struct DocumentListPane: View {
    // Extension-visible: +Organise
    @Environment(DocumentStore.self) var store
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedItem: ContentListItem?
    // Extension-visible: +Organise
    @State var searchText = ""
    // Extension-visible: +Organise
    @State var filterMode: DocFilterMode = .all
    // Extension-visible: +Organise
    @State var sortOrder: DocSortOrder = .modifiedNewest
    @State private var renamingDocID: UUID?
    @State private var renameText = ""
    /// Which row is showing its "⋯", so that row's trailing badges can step aside for it.
    @State private var revealedRowID: UUID?
    @FocusState private var isRenameFieldFocused: Bool
    @State private var hasAutoSelected = false
    // Extension-visible: +Organise
    /// Active saved view, when one is chosen instead of a built-in filter.
    @State var activeSavedViewID: UUID?
    // Extension-visible: +Organise
    /// Active type filter, when one is chosen.
    @State var activeTypeName: String?
    // Extension-visible: +Organise
    /// The naming prompt currently up, if any.
    @State var organisePrompt: OrganisePrompt?
    /// Documents ticked for a bulk action. Non-empty shows the bulk bar.
    @State private var bulkSelection: Set<UUID> = []
    @State private var bulkTagText = ""
    @State private var showingBulkTagField = false

    private var filteredDocs: [WritingDocument] {
        let base: [WritingDocument] = if let activeSavedViewID {
            store.documents(matching: activeSavedViewID)
        } else if let activeTypeName {
            store.activeDocuments.filter { $0.typeName == activeTypeName }
        } else {
            switch filterMode {
            case .all: store.activeDocuments
            case .inbox: store.inboxDocuments
            case .recent: store.recentDocuments
            case .pinned: store.pinnedDocuments
            }
        }
        let searched: [WritingDocument] = if searchText.isEmpty {
            base
        } else {
            base.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                    $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }
        return sorted(searched)
    }

    private func sorted(_ docs: [WritingDocument]) -> [WritingDocument] {
        switch sortOrder {
        case .modifiedNewest: docs.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest: docs.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAZ: docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA: docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .createdNewest: docs.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: docs.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        listView
            .searchable(text: $searchText, prompt: "Search documents")
            .navigationTitle("Documents")
            .sheet(item: $organisePrompt) { prompt in
                OrganiseNamingSheet(prompt: prompt) { name in
                    commitOrganisePrompt(prompt, name: name)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Filter
                        Section("Filter") {
                            ForEach(DocFilterMode.allCases, id: \.rawValue) { mode in
                                Button {
                                    filterMode = mode
                                    activeSavedViewID = nil
                                    activeTypeName = nil
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

                        Section("Views") {
                            ForEach(store.savedViews) { view in
                                Button {
                                    activeSavedViewID = view.id
                                    activeTypeName = nil
                                } label: {
                                    HStack {
                                        Label(view.name, systemImage: view.symbolName)
                                        if activeSavedViewID == view.id {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button {
                                organisePrompt = .newView
                            } label: {
                                Label("Save Current Filter as View…", systemImage: "plus")
                            }

                            if let active = store.savedViews.first(where: { $0.id == activeSavedViewID }) {
                                Button {
                                    organisePrompt = .renameView(active)
                                } label: {
                                    Label("Rename This View…", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleteSavedView(active)
                                } label: {
                                    Label("Delete This View", systemImage: "trash")
                                }
                            }
                        }

                        if !store.documentTypes.isEmpty {
                            Section("Types") {
                                ForEach(DocumentType.ordered(store.documentTypes)) { type in
                                    Button {
                                        activeTypeName = type.name
                                        activeSavedViewID = nil
                                    } label: {
                                        HStack {
                                            Label(type.name, systemImage: type.symbolName)
                                            if activeTypeName == type.name {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }

                                if let active = store.documentTypes.first(where: { $0.name == activeTypeName }) {
                                    Divider()
                                    Button {
                                        organisePrompt = .renameType(active)
                                    } label: {
                                        Label("Rename This Type…", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        deleteType(active)
                                    } label: {
                                        Label("Delete This Type", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        // Sort
                        Section("Sort By") {
                            ForEach(DocSortOrder.allCases, id: \.rawValue) { order in
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Filter and Sort Options")
                    .accessibilityHint("Opens menu to filter, sort, and configure document view")
                    .help("Filter, Sort & View Options")
                }
            }
            .onAppear {
                hasAutoSelected = false
                autoSelectFirst()
            }
            .onChange(of: store.activeDocuments.count) { _, _ in
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

    // MARK: - Auto-select first

    private func autoSelectFirst() {
        guard !hasAutoSelected, selectedItem == nil else { return }

        // If no documents exist, create one
        if store.activeDocuments.isEmpty {
            let newDoc = store.createDocument()
            selectedItem = .document(newDoc.id)
            hasAutoSelected = true
            return
        }

        // Otherwise select the first document
        if let first = filteredDocs.first {
            selectedItem = .document(first.id)
            hasAutoSelected = true
        }
    }

    // MARK: - List View

    private var listView: some View {
        VStack(spacing: 0) {
            if filterMode == .inbox, activeSavedViewID == nil, activeTypeName == nil {
                inboxHeader
            }
            if !bulkSelection.isEmpty {
                bulkActionBar
            }
            documentList
        }
    }

    /// Explains the inbox rather than showing an unexplained subset of documents.
    private var inboxHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(store.inboxCount) to organise")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }

    /// Shown while documents are ticked. Every action here is reversible except
    /// Trash, which moves to Trash rather than deleting outright.
    private var bulkActionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("\(bulkSelection.count) selected")
                    .font(.caption.weight(.medium))

                Spacer()

                Button("Tag") { showingBulkTagField.toggle() }
                    .font(.caption)

                if filterMode == .inbox {
                    Button("Organise") {
                        store.applyBulk(to: bulkSelection) { BulkAction.markingOrganised($0) }
                        bulkSelection.removeAll()
                    }
                    .font(.caption)
                }

                Button("Trash", role: .destructive) {
                    store.applyBulk(to: bulkSelection) { BulkAction.trashing($0) }
                    bulkSelection.removeAll()
                }
                .font(.caption)

                Button("Clear") { bulkSelection.removeAll() }
                    .font(.caption)
            }

            if showingBulkTagField {
                HStack(spacing: 6) {
                    TextField("Tag name", text: $bulkTagText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(applyBulkTag)
                    Button("Add", action: applyBulkTag)
                        .font(.caption)
                        .disabled(bulkTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppThemeConstants.accent.opacity(0.10))
    }

    private func applyBulkTag() {
        let tag = bulkTagText
        guard !tag.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.applyBulk(to: bulkSelection) { BulkAction.addingTag(tag, to: $0) }
        bulkTagText = ""
        showingBulkTagField = false
        bulkSelection.removeAll()
    }

    private var documentList: some View {
        List(selection: $selectedItem) {
            ForEach(filteredDocs) { doc in
                if renamingDocID == doc.id {
                    renameField(for: doc)
                        .tag(ContentListItem.document(doc.id))
                } else {
                    DocumentListRow(document: doc, isRevealed: revealedRowID == doc.id)
                        .tag(ContentListItem.document(doc.id))
                        .accessibilityLabel("\(doc.title)\(doc.isPinned ? ", pinned" : "")")
                        .accessibilityHint("Opens this document")
                        .sidebarRowMenu(revealed: $revealedRowID.isRevealed(doc.id)) {
                            docContextMenu(for: doc)
                        }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
        .overlay {
            if !store.isLoaded {
                ContentLoadingView()
            } else if filteredDocs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Documents" : "No Results",
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass"
                )
            }
        }
    }

    // MARK: - Rename

    private func renameField(for doc: WritingDocument) -> some View {
        TextField("Title", text: $renameText, onCommit: {
            store.renameDocument(id: doc.id, newTitle: renameText)
            renamingDocID = nil
        })
        .focused($isRenameFieldFocused)
        .textFieldStyle(.plain)
        .font(.subheadline.weight(.medium))
        .padding(.vertical, 4)
        .onExitCommand {
            renamingDocID = nil
        }
        .onAppear {
            renameText = doc.title
            isRenameFieldFocused = true
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func docContextMenu(for doc: WritingDocument) -> some View {
        Button(bulkSelection.contains(doc.id) ? "Deselect" : "Select for bulk action") {
            if bulkSelection.contains(doc.id) {
                bulkSelection.remove(doc.id)
            } else {
                bulkSelection.insert(doc.id)
            }
        }

        if !store.documentTypes.isEmpty {
            Menu("Set Type") {
                Button("New Type from This Document…") {
                    organisePrompt = .newType(doc)
                }
                Divider()
                ForEach(DocumentType.ordered(store.documentTypes)) { type in
                    Button(type.name) { store.applyType(type, to: doc.id) }
                }
            }
        }

        Button(doc.isOrganised ? "Move to Inbox" : "Mark Organised") {
            if doc.isOrganised {
                var updated = doc
                updated.isOrganised = false
                store.updateDocument(updated)
            } else {
                store.markOrganised(id: doc.id)
            }
        }

        Divider()

        Button {
            store.togglePin(id: doc.id)
        } label: {
            Label(
                doc.isPinned ? "Unpin" : "Pin",
                systemImage: doc.isPinned ? "pin.slash" : "pin"
            )
        }
        Button {
            renameText = doc.title
            renamingDocID = doc.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            PDFExportService.export(document: doc)
        } label: {
            Label("Export as PDF", systemImage: "arrow.down.doc")
        }
        Divider()
        Button(role: .destructive) {
            store.deleteDocument(id: doc.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}
