import SwiftUI

// MARK: - Sort & Filter Options

enum DocSortOrder: String, CaseIterable {
    case modifiedNewest = "Last Modified"
    case modifiedOldest = "Oldest Modified"
    case titleAZ = "Title A–Z"
    case titleZA = "Title Z–A"
    case createdNewest = "Newest Created"
    case createdOldest = "Oldest Created"

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
    case pinned = "Pinned"
    case recent = "Recent"

    var icon: String {
        switch self {
        case .all: "doc.text"
        case .pinned: "pin"
        case .recent: "clock"
        }
    }
}

// MARK: - DocumentListPane

/// Column 2 content when Documents category is selected.
/// Shows search, filter/sort/view menus, and a selectable document list or gallery.
struct DocumentListPane: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedItem: ContentListItem?
    @State private var searchText = ""
    @State private var filterMode: DocFilterMode = .all
    @State private var sortOrder: DocSortOrder = .modifiedNewest
    @State private var renamingDocID: UUID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var hasAutoSelected = false

    private var filteredDocs: [WritingDocument] {
        let base: [WritingDocument] = switch filterMode {
        case .all: store.activeDocuments
        case .recent: store.recentDocuments
        case .pinned: store.pinnedDocuments
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Filter
                        Section("Filter") {
                            ForEach(DocFilterMode.allCases, id: \.rawValue) { mode in
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
        List(selection: $selectedItem) {
            ForEach(filteredDocs) { doc in
                if renamingDocID == doc.id {
                    renameField(for: doc)
                        .tag(ContentListItem.document(doc.id))
                } else {
                    DocumentListRow(document: doc)
                        .tag(ContentListItem.document(doc.id))
                        .accessibilityLabel("\(doc.title)\(doc.isPinned ? ", pinned" : "")")
                        .accessibilityHint("Opens this document")
                        .contextMenu { docContextMenu(for: doc) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
        .overlay {
            if filteredDocs.isEmpty {
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
