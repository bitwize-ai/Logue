import SwiftUI

/// Full-width content view that lists documents, used when
/// "All Documents" is selected in the sidebar.
struct DocumentListContentView: View {
    let spaceID: UUID?
    @Environment(DocumentStore.self) private var store
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @AppStorage(AppConstants.UserDefaultsKeys.documentSortOrder) private var sortOrderRaw = DocSortOrder.modifiedNewest.rawValue
    @State private var filterMode: DocFilterMode = .all
    @State private var selectedTagFilter: String?
    @State private var showRenameAlert = false
    @State private var renamingDocID: UUID?
    @State private var renameText = ""
    @AppStorage(AppConstants.UserDefaultsKeys.documentViewMode) private var viewModeRaw = ContentViewMode.list.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.groupByDate) private var groupByDate = true

    private var viewMode: ContentViewMode {
        ContentViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var sortOrder: DocSortOrder {
        get { DocSortOrder(rawValue: sortOrderRaw) ?? .modifiedNewest }
        set { sortOrderRaw = newValue.rawValue }
    }

    private var groupedDocuments: [DateGroupingHelper.Group<WritingDocument>]? {
        guard groupByDate, sortOrder.isDateBased, let kp = sortOrder.dateKeyPath else { return nil }
        let groups = DateGroupingHelper.group(documents, by: kp)
        return groups.isEmpty ? nil : groups
    }

    private var documents: [WritingDocument] {
        let active = store.activeDocuments
        let base: [WritingDocument] = if let spaceID {
            active.filter { $0.spaceID == spaceID }
        } else {
            active
        }

        let filtered: [WritingDocument] = switch filterMode {
        case .all: base
        case .pinned: base.filter(\.isPinned)
        case .recent: Array(base.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(10))
        }

        let tagged: [WritingDocument] = if let tag = selectedTagFilter {
            filtered.filter { $0.tags.contains(tag) }
        } else {
            filtered
        }

        let searched: [WritingDocument] = if debouncedSearchText.isEmpty {
            tagged
        } else {
            tagged.filter {
                $0.title.localizedCaseInsensitiveContains(debouncedSearchText) ||
                    $0.body.localizedCaseInsensitiveContains(debouncedSearchText)
            }
        }

        return sorted(searched)
    }

    private func sorted(_ docs: [WritingDocument]) -> [WritingDocument] {
        let base: [WritingDocument] = switch sortOrder {
        case .modifiedNewest: docs.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest: docs.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAZ: docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA: docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .createdNewest: docs.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: docs.sorted { $0.createdAt < $1.createdAt }
        }
        // Pin favorited documents to the top while preserving sort order within each group
        return base.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return false // preserve existing order
        }
    }

    private var title: String {
        if let spaceID, let space = spaceStore.space(for: spaceID) {
            return space.name
        }
        return "All Documents"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.allTags.isEmpty, spaceID == nil {
                tagFilterBar
                Divider()
            }

            if documents.isEmpty {
                emptyState
            } else if viewMode == .grid {
                documentGrid
            } else {
                documentList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .onDisappear { searchDebounceTask?.cancel() }
        .alert("Rename Document", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let id = renamingDocID {
                    store.renameDocument(id: id, newTitle: trimmed)
                }
                renamingDocID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingDocID = nil
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(documents.count) document\(documents.count == 1 ? "" : "s")")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search documents")
        .toolbar {
            docListToolbarContent
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.searchDebounce)
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var docListToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                let doc = store.createDocument(inSpace: spaceID)
                store.selectedDocumentID = doc.id
            } label: {
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("New Document")
            }
            .help("New Document")
        }
        ToolbarItemGroup(placement: .primaryAction) {
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
                Section("Sort By") {
                    ForEach(DocSortOrder.allCases, id: \.rawValue) { order in
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
            .help("Options")
            .accessibilityLabel("Options")

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

    // MARK: - Document Grid

    private var documentGrid: some View {
        let gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]
        return ScrollView {
            if let groups = groupedDocuments {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.label) { section in
                        dateGroupHeader(section.label)
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(section.items) { doc in
                                documentGridCard(doc)
                            }
                        }
                    }
                }
                .padding(24)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(documents) { doc in
                        documentGridCard(doc)
                    }
                }
                .padding(24)
            }
        }
    }

    private func documentGridCard(_ doc: WritingDocument) -> some View {
        // Keep card height consistent: if title is long enough to wrap to 2 lines,
        // reduce snippet lines from 4 to 3 so total content stays the same.
        let titleIsLong = doc.title.count > 30
        let snippetLines = titleIsLong ? 3 : 4

        return HomeCardShell {
            store.selectedDocumentID = doc.id
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if doc.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(AppThemeConstants.pinnedColor)
                    }
                }

                Text(doc.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(doc.snippet.isEmpty ? "Empty document" : doc.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(snippetLines)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack {
                    Text("\(doc.wordCount)w")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        } contextMenu: {
            docContextMenu(for: doc)
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let groups = groupedDocuments {
                    ForEach(groups, id: \.label) { section in
                        dateGroupHeader(section.label)
                        ForEach(section.items) { doc in
                            documentRow(doc)
                        }
                    }
                } else {
                    ForEach(documents) { doc in
                        documentRow(doc)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func dateGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func documentRow(_ doc: WritingDocument) -> some View {
        let pinnedLabel = doc.isPinned ? "pinned, " : ""
        let modifiedLabel = doc.modifiedAt.formatted(.relative(presentation: .named))
        let axLabel = "\(doc.title), \(doc.wordCount) words, \(pinnedLabel)modified \(modifiedLabel)"
        return HomeCardShell(
            action: { store.selectedDocumentID = doc.id },
            accessibilityLabel: axLabel,
            accessibilityHint: "Opens document",
            content: { _ in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(doc.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if doc.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppThemeConstants.pinnedColor)
                            }
                        }
                        Text(doc.snippet.isEmpty ? "Empty document" : doc.snippet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("\(doc.wordCount) words")
                            Text("\u{00B7}")
                            Text(doc.readingTimeLabel)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            },
            contextMenu: { docContextMenu(for: doc) }
        )
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func docContextMenu(for doc: WritingDocument) -> some View {
        Button {
            store.selectedDocumentID = doc.id
        } label: {
            Label("Open", systemImage: "doc.text")
        }
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
            showRenameAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        if !spaceStore.topLevelSpaces.isEmpty || doc.spaceID != nil {
            Menu("Move to") {
                HierarchicalSpaceMenu(currentSpaceID: doc.spaceID) { newSpaceID in
                    store.moveDocument(id: doc.id, toSpace: newSpaceID)
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
            store.deleteDocument(id: doc.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Documents" : "No Results",
                systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass"
            )
        } description: {
            if searchText.isEmpty {
                Text("Create a new document to get started.")
            } else {
                Text("No documents match '\(searchText)'")
            }
        } actions: {
            if searchText.isEmpty {
                Button("New Document") {
                    let doc = store.createDocument(inSpace: spaceID)
                    store.selectedDocumentID = doc.id
                }
                .buttonStyle(.borderedProminent)
                .tint(AppThemeConstants.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
