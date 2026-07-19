import SwiftUI

// MARK: - Trash Item

private enum TrashItem: Identifiable {
    case document(WritingDocument)
    case meeting(MeetingNote)

    var id: UUID {
        switch self {
        case let .document(doc): doc.id
        case let .meeting(note): note.id
        }
    }

    var title: String {
        switch self {
        case let .document(doc): doc.title
        case let .meeting(note): note.title
        }
    }

    var icon: String {
        switch self {
        case .document: "doc.text"
        case let .meeting(note): note.recordingMode.iconName
        }
    }

    var iconColor: Color {
        switch self {
        case .document: AppThemeConstants.categoryPurple
        case .meeting: AppThemeConstants.accent
        }
    }

    var typeBadge: String {
        switch self {
        case .document: "Document"
        case .meeting: "Meeting"
        }
    }

    var trashedAt: Date? {
        switch self {
        case let .document(doc): doc.trashedAt
        case let .meeting(note): note.trashedAt
        }
    }

    var subtitle: String {
        switch self {
        case let .document(doc):
            return "\(doc.wordCount) words"
        case let .meeting(note):
            var parts: [String] = []
            if note.duration > 0 {
                parts.append(note.formattedDuration)
            }
            if !note.segments.isEmpty {
                parts.append("\(note.segments.count) segments")
            }
            return parts.isEmpty ? "Meeting" : parts.joined(separator: " \u{00B7} ")
        }
    }
}

// MARK: - TrashListPane

/// Shows all trashed documents and meetings with restore and permanent delete actions.
struct TrashListPane: View {
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var showEmptyConfirmation = false
    @AppStorage(AppConstants.UserDefaultsKeys.trashViewMode) private var viewModeRaw = ContentViewMode.list.rawValue

    private var viewMode: ContentViewMode {
        ContentViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var allTrashItems: [TrashItem] {
        let docs: [TrashItem] = documentStore.trashedDocuments.map { .document($0) }
        let meetings: [TrashItem] = meetingStore.trashedMeetings.map { .meeting($0) }
        return (docs + meetings).sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    private var trashItems: [TrashItem] {
        guard !searchText.isEmpty else { return allTrashItems }
        return allTrashItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if allTrashItems.isEmpty {
                emptyState
            } else if trashItems.isEmpty {
                searchEmptyState
            } else if viewMode == .grid {
                trashGrid
            } else {
                trashList
            }
        }
        .background(AppThemeConstants.contentBackground)
        .navigationTitle("Trash")
        .navigationSubtitle("\(allTrashItems.count) item\(allTrashItems.count == 1 ? "" : "s")")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search trash")
        .toolbar {
            trashToolbarContent
        }
        .alert("Empty Trash?", isPresented: $showEmptyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                documentStore.emptyDocumentTrash()
                meetingStore.emptyMeetingTrash()
            }
        } message: {
            Text("This will permanently delete all \(allTrashItems.count) item\(allTrashItems.count == 1 ? "" : "s"). This action cannot be undone.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var trashToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !allTrashItems.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModeRaw = viewMode == .list
                            ? ContentViewMode.grid.rawValue
                            : ContentViewMode.list.rawValue
                    }
                } label: {
                    Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(viewMode == .list ? "Switch to Grid View" : "Switch to List View")
                .accessibilityHint("Toggles between list and grid layout")
                .help(viewMode == .list ? "Grid View" : "List View")

                Button(role: .destructive) {
                    showEmptyConfirmation = true
                } label: {
                    Label("Empty Trash", systemImage: "trash.slash")
                }
                .accessibilityLabel("Empty Trash")
                .accessibilityHint("Permanently deletes all items in trash")
                .help("Permanently delete all items in Trash")
            }
        }
    }

    // MARK: - Trash List

    private var trashList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(trashItems) { item in
                    trashRow(item)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func trashRow(_ item: TrashItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.typeBadge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            item.iconColor.opacity(AppThemeConstants.opacityLight),
                            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                        )
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let trashedAt = item.trashedAt {
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("Deleted \(trashedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(AppThemeConstants.borderColor, lineWidth: 0.5)
        )
        .accessibilityLabel("\(item.title), \(item.typeBadge)")
        .accessibilityHint("Right-click to restore or permanently delete")
        .contextMenu {
            trashItemContextMenu(item)
        }
    }

    // MARK: - Trash Grid

    private var trashGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)],
                spacing: 16
            ) {
                ForEach(trashItems) { item in
                    trashGridCard(item)
                }
            }
            .padding(24)
        }
    }

    private func trashGridCard(_ item: TrashItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(item.iconColor)
                Spacer()
                Text(item.typeBadge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        item.iconColor.opacity(AppThemeConstants.opacityLight),
                        in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusXSmall)
                    )
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let trashedAt = item.trashedAt {
                Text("Deleted \(trashedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .fill(AppThemeConstants.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .stroke(AppThemeConstants.borderColor, lineWidth: 0.5)
        )
        .accessibilityLabel("\(item.title), \(item.typeBadge)")
        .accessibilityHint("Right-click to restore or permanently delete")
        .contextMenu {
            trashItemContextMenu(item)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func trashItemContextMenu(_ item: TrashItem) -> some View {
        Button {
            restoreItem(item)
        } label: {
            Label("Put Back", systemImage: "arrow.uturn.backward")
        }
        Divider()
        Button(role: .destructive) {
            permanentlyDeleteItem(item)
        } label: {
            Label("Delete Permanently", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func restoreItem(_ item: TrashItem) {
        switch item {
        case let .document(doc):
            documentStore.restoreDocument(id: doc.id)
        case let .meeting(note):
            meetingStore.restoreMeeting(id: note.id)
        }
    }

    private func permanentlyDeleteItem(_ item: TrashItem) {
        switch item {
        case let .document(doc):
            documentStore.permanentlyDeleteDocument(id: doc.id)
        case let .meeting(note):
            meetingStore.permanentlyDeleteMeeting(id: note.id)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Trash is Empty", systemImage: "trash")
        } description: {
            Text("Items you delete will appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchEmptyState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No items match '\(searchText)'")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
