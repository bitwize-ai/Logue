import SwiftUI

// MARK: - Command Item

struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let category: CommandCategory
    let action: () -> Void

    init(_ title: String, icon: String, category: CommandCategory, subtitle: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.action = action
    }
}

enum CommandCategory: String, CaseIterable {
    case navigation = "Navigation"
    case create = "Create"
    case document = "Documents"
    case meeting = "Meetings"
    case actionItem = "Action Items"
    case ai = "AI Tools"
}

// MARK: - Command Palette View

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let commands: [CommandItem]

    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var liveContentResults: [CommandItem] = []
    @State private var isSearching = false
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    /// Categories whose results come from live content search rather than the static commands list.
    /// When the user types a query, static entries in these categories are suppressed (live search covers them).
    private static let liveContentCategories: Set<CommandCategory> = [.document, .meeting, .actionItem]

    private var filteredStaticCommands: [CommandItem] {
        guard !searchText.isEmpty else { return commands }
        let query = searchText.lowercased()
        return commands.filter { command in
            // When searching, suppress static content entries — live search covers these.
            guard !Self.liveContentCategories.contains(command.category) else { return false }
            return command.title.lowercased().contains(query)
                || (command.subtitle?.lowercased().contains(query) ?? false)
                || command.category.rawValue.lowercased().contains(query)
        }
    }

    private var combinedCommands: [CommandItem] {
        searchText.isEmpty
            ? filteredStaticCommands
            : filteredStaticCommands + liveContentResults
    }

    private var groupedCommands: [(CommandCategory, [CommandItem])] {
        let grouped = Dictionary(grouping: combinedCommands, by: \.category)
        return CommandCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    private var flatFilteredCommands: [CommandItem] {
        groupedCommands.flatMap(\.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .accessibilityLabel("Command search")
                    .accessibilityHint("Type to search for commands")
                    .onSubmit {
                        executeSelected()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Clears the command search text")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if isSearching, flatFilteredCommands.isEmpty {
                // Shimmer rows while the debounced FTS search is in flight — gives users
                // a sense of "where results will appear" rather than a bare spinner.
                VStack(spacing: 0) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        SkeletonRow()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if flatFilteredCommands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "Type to search" : "No results for \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupedCommands, id: \.0) { category, items in
                                Text(category.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)

                                ForEach(items) { item in
                                    let index = flatFilteredCommands.firstIndex(where: { $0.id == item.id }) ?? 0
                                    CommandRow(
                                        item: item,
                                        isSelected: index == selectedIndex
                                    ) {
                                        execute(item)
                                    }
                                    .id(item.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < flatFilteredCommands.count {
                            proxy.scrollTo(flatFilteredCommands[newIndex].id)
                        }
                    }
                }
            }

            // Footer
            Divider()
            HStack(spacing: 16) {
                footerHint(icon: "arrow.up.arrow.down", text: "Navigate")
                footerHint(icon: "return", text: "Select")
                footerHint(icon: "escape", text: "Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 520)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusXLarge, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(
            color: .black.opacity(AppThemeConstants.panelShadowOpacity),
            radius: AppThemeConstants.panelShadowRadius,
            x: 0,
            y: AppThemeConstants.panelShadowY
        )
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
        .onChange(of: searchText) { _, newValue in
            selectedIndex = 0
            searchDebounceTask?.cancel()

            if newValue.isEmpty {
                liveContentResults = []
                isSearching = false
                return
            }

            isSearching = true
            searchDebounceTask = Task {
                try? await Task.sleep(for: AppConstants.Delays.searchDebounce)
                guard !Task.isCancelled else { return }
                let results = await runContentSearch(query: newValue)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard searchText == newValue else { return }
                    liveContentResults = results
                    isSearching = false
                }
            }
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < flatFilteredCommands.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
    }

    // MARK: - Content Search

    /// Runs a unified content search across documents, meetings, and action items.
    /// Uses MeetingMemoryIndex FTS5 for transcript matches and in-memory matching for the rest.
    @MainActor
    private func runContentSearch(query: String) async -> [CommandItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let meetingResults = searchMeetings(query: trimmed)
        let documentResults = searchDocuments(query: trimmed)
        let actionItemResults = searchActionItems(query: trimmed)

        return await meetingResults + documentResults + actionItemResults
    }

    private func searchDocuments(query: String) -> [CommandItem] {
        let lowered = query.lowercased()
        return documentStore.activeDocuments
            .filter { doc in
                doc.title.lowercased().contains(lowered)
                    || doc.body.lowercased().contains(lowered)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(8)
            .map { doc in
                let snippet = documentSnippet(for: doc, query: lowered)
                return CommandItem(
                    doc.title.isEmpty ? "Untitled Document" : doc.title,
                    icon: "doc.text",
                    category: .document,
                    subtitle: snippet
                ) {
                    documentStore.selectedDocumentID = doc.id
                }
            }
    }

    private func documentSnippet(for doc: WritingDocument, query: String) -> String? {
        if doc.title.lowercased().contains(query) {
            return doc.body.isEmpty ? nil : String(doc.body.prefix(80))
        }
        guard let range = doc.body.lowercased().range(of: query) else {
            return doc.body.isEmpty ? nil : String(doc.body.prefix(80))
        }
        let center = doc.body.distance(from: doc.body.startIndex, to: range.lowerBound)
        let start = max(0, center - 40)
        let startIdx = doc.body.index(doc.body.startIndex, offsetBy: start)
        let remaining = doc.body.distance(from: startIdx, to: doc.body.endIndex)
        let endIdx = doc.body.index(startIdx, offsetBy: min(120, remaining))
        var snippet = String(doc.body[startIdx ..< endIdx])
        if start > 0 {
            snippet = "…" + snippet
        }
        if endIdx < doc.body.endIndex {
            snippet += "…"
        }
        return snippet
    }

    private func searchMeetings(query: String) async -> [CommandItem] {
        let matches = await meetingStore.searchMeetings(query: query)
        let lowered = query.lowercased()
        return matches
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(8)
            .map { meeting in
                let subtitle = meetingSubtitle(for: meeting, query: lowered)
                return CommandItem(
                    meeting.title,
                    icon: "waveform",
                    category: .meeting,
                    subtitle: subtitle
                ) {
                    meetingStore.selectedMeetingID = meeting.id
                }
            }
    }

    private func meetingSubtitle(for meeting: MeetingNote, query: String) -> String {
        let date = meeting.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let summary = meeting.summary, summary.lowercased().contains(query) {
            return date + " · " + String(summary.prefix(100))
        }
        if let segment = meeting.segments.first(where: { $0.text.lowercased().contains(query) }) {
            return date + " · " + String(segment.text.prefix(100))
        }
        if let tag = meeting.tags.first(where: { $0.lowercased().contains(query) }) {
            return date + " · #\(tag)"
        }
        return date
    }

    private func searchActionItems(query: String) -> [CommandItem] {
        let lowered = query.lowercased()
        var results: [CommandItem] = []
        for meeting in meetingStore.activeMeetings where !meeting.isArchived {
            for item in meeting.actionItems where item.title.lowercased().contains(lowered) {
                let status = item.isCompleted ? "✓ " : ""
                let subtitle = "\(status)\(meeting.title)"
                let meetingID = meeting.id
                results.append(CommandItem(
                    item.title,
                    icon: "checklist",
                    category: .actionItem,
                    subtitle: subtitle
                ) {
                    meetingStore.selectedMeetingID = meetingID
                })
                if results.count >= 6 {
                    return results
                }
            }
        }
        return results
    }

    // MARK: - Execution

    private func executeSelected() {
        guard selectedIndex < flatFilteredCommands.count else { return }
        execute(flatFilteredCommands[selectedIndex])
    }

    private func execute(_ item: CommandItem) {
        isPresented = false
        item.action()
    }

    private func footerHint(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AppThemeConstants.accent
                        .opacity(AppThemeConstants.opacityMedium) : (isHovered ? Color.primary.opacity(AppThemeConstants.opacityLight) : Color.clear))
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle ?? "Executes this command")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
