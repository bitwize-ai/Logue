import SwiftUI

/// Column 2 content when Overview category is selected.
/// Shows recent meetings and documents with universal search.
struct OverviewPane: View {
    @Environment(DocumentStore.self) private var store
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedItem: ContentListItem?
    @Binding var selectedCategory: SidebarCategory

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var searchResults: [(id: UUID, title: String, type: String, item: ContentListItem)] = []

    var body: some View {
        Group {
            if searchText.isEmpty {
                recentsListView
            } else {
                searchResultsView
            }
        }
        .searchable(text: $searchText, prompt: "Search")
        .navigationTitle("Home")
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                searchResults = []
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.searchDebounce)
                    guard !Task.isCancelled else { return }

                    // FTS5 search for meetings (async, off main thread)
                    let ftsIDs = await MeetingMemoryIndex.shared.searchMatchingIDs(query: newValue)
                    guard !Task.isCancelled else { return }

                    // Build results on main actor
                    var results: [(id: UUID, title: String, type: String, item: ContentListItem)] = []

                    // Documents: title-only search (body search is too expensive per keystroke)
                    let matchingDocs = store.activeDocuments.filter {
                        $0.title.localizedCaseInsensitiveContains(newValue)
                    }
                    for doc in matchingDocs {
                        results.append((id: doc.id, title: doc.title, type: "Document", item: .document(doc.id)))
                    }

                    // Meetings: title + summary (lightweight) + FTS5 index (transcript/keywords)
                    let matchingMeetings = meetingStore.activeMeetings.filter {
                        $0.title.localizedCaseInsensitiveContains(newValue)
                            || ($0.summary?.localizedCaseInsensitiveContains(newValue) ?? false)
                            || ftsIDs.contains($0.id)
                    }
                    for meeting in matchingMeetings {
                        results.append((id: meeting.id, title: meeting.title, type: "Meeting", item: .meeting(meeting.id)))
                    }

                    searchResults = results
                    debouncedSearchText = newValue
                }
            }
        }
    }

    // MARK: - Recents List View

    private var recentsListView: some View {
        List {
            recentMeetingsSection
            recentDocumentsSection
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Recent Meetings

    private var recentMeetingsSection: some View {
        Section {
            let recentMeetings = meetingStore.meetings
                .filter { !$0.isArchived }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(10)

            if recentMeetings.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        Text("No meetings yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(Array(recentMeetings)) { meeting in
                    Button {
                        selectedItem = .meeting(meeting.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: meeting.recordingMode.iconName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(meeting.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                    if meeting.duration > 0 {
                                        Text("\u{2022}")
                                        Text(meeting.formattedDuration)
                                            .font(.caption2.monospacedDigit())
                                    }
                                }
                                .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if meeting.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppThemeConstants.pinnedColor)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Recent Meetings")
                Spacer()
                Button {
                    selectedCategory = .meetings
                } label: {
                    Text("View All")
                        .font(.caption)
                        .textCase(nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all meetings")
            }
        }
    }

    // MARK: - Recent Documents

    private var recentDocumentsSection: some View {
        Section {
            let recentDocs = store.documents
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(10)

            if recentDocs.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        Text("No documents yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(Array(recentDocs)) { doc in
                    Button {
                        selectedItem = .document(doc.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(doc.modifiedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if doc.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppThemeConstants.pinnedColor)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Recent Documents")
                Spacer()
                Button {
                    selectedCategory = .documents
                } label: {
                    Text("View All")
                        .font(.caption)
                        .textCase(nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all documents")
            }
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        List {
            if searchResults.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No documents or meetings match '\(searchText)'")
                )
            } else {
                ForEach(searchResults, id: \.id) { result in
                    Button {
                        selectedItem = result.item
                        searchText = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.type == "Document" ? "doc.text" : "waveform")
                                .font(.title3)
                                .foregroundStyle(result.type == "Document" ? AppThemeConstants.success : AppThemeConstants.brandPrimary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(result.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(AppThemeConstants.surfaceBackground)
    }
}
