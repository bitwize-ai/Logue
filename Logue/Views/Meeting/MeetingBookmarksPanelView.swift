import SwiftUI

/// Right panel listing all bookmarks for a meeting with tap-to-scroll.
struct MeetingBookmarksPanelView: View {
    @Environment(MeetingStore.self) private var store
    let meeting: MeetingNote
    @Binding var scrollToSegmentID: UUID?
    @State private var editingBookmarkID: UUID?
    @State private var editLabel = ""
    @FocusState private var isEditFocused: Bool

    private static let typePresets: [(label: String, color: BookmarkColor)] = [
        ("Key Decision", .blue),
        ("Action Item", .orange),
        ("Important", .red),
        ("Question", .purple),
    ]

    var body: some View {
        Group {
            if meeting.bookmarks.isEmpty {
                EmptyStateView(
                    icon: "bookmark",
                    title: "No bookmarks yet",
                    description: "Add bookmarks during recording or click the bookmark icon on any transcript segment."
                )
            } else {
                List {
                    ForEach(meeting.bookmarks) { bookmark in
                        if editingBookmarkID == bookmark.id {
                            editRow(bookmark)
                                .listRowSeparator(.visible)
                        } else {
                            displayRow(bookmark)
                                .listRowSeparator(.visible)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppThemeConstants.surfaceBackground)
    }

    // MARK: - Display Row

    private func displayRow(_ bookmark: Bookmark) -> some View {
        Button {
            scrollToBookmark(bookmark)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(bookmark.color.swiftUIColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("\(bookmark.color.rawValue) bookmark")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(bookmark.label.isEmpty ? "Bookmark" : bookmark.label)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if bookmark.source == .ai {
                            aiSourceBadge
                        }
                    }

                    if let preview = nearestSegmentText(for: bookmark) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(bookmark.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { bookmarkContextMenu(bookmark) }
        .accessibilityHint(bookmark.source == .ai ? "AI-generated highlight" : "User bookmark")
    }

    private var aiSourceBadge: some View {
        Image(systemName: "sparkles")
            .font(.caption2)
            .foregroundStyle(AppThemeConstants.brandPrimary)
            .help("AI-generated highlight")
            .accessibilityHidden(true)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func bookmarkContextMenu(_ bookmark: Bookmark) -> some View {
        Menu("Change Type") {
            ForEach(Self.typePresets, id: \.label) { preset in
                Button {
                    var updated = bookmark
                    updated.label = preset.label
                    updated.color = preset.color
                    store.updateBookmark(updated, in: meeting.id)
                } label: {
                    HStack {
                        Text(preset.label)
                        if bookmark.label == preset.label {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Button("Rename") {
            editLabel = bookmark.label
            editingBookmarkID = bookmark.id
        }

        Divider()

        Button("Delete", role: .destructive) {
            store.removeBookmark(bookmarkID: bookmark.id, from: meeting.id)
        }
    }

    // MARK: - Edit Row

    private func editRow(_ bookmark: Bookmark) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bookmark.color.swiftUIColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("\(bookmark.color.rawValue) bookmark")

            TextField("Label", text: $editLabel)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .focused($isEditFocused)
                // A21: Replaced DispatchQueue.main.asyncAfter with Task.sleep
                .onAppear {
                    Task {
                        try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                        isEditFocused = true
                        try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
                .onSubmit { commitEdit(bookmark) }

            Button {
                commitEdit(bookmark)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("Save bookmark")
            .accessibilityLabel("Save bookmark")

            Button {
                editingBookmarkID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel edit")
            .accessibilityLabel("Cancel edit")
        }
    }

    private func commitEdit(_ bookmark: Bookmark) {
        var updated = bookmark
        updated.label = editLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateBookmark(updated, in: meeting.id)
        editingBookmarkID = nil
    }

    // MARK: - Helpers

    private func nearestSegmentText(for bookmark: Bookmark) -> String? {
        let sorted = meeting.segments.sorted { $0.startTime < $1.startTime }
        if let match = sorted.last(where: { $0.startTime <= bookmark.timestamp }) {
            return match.text
        }
        return sorted.first?.text
    }

    // MARK: - Scroll

    private func scrollToBookmark(_ bookmark: Bookmark) {
        let sorted = meeting.segments.sorted { $0.startTime < $1.startTime }
        if let match = sorted.last(where: { $0.startTime <= bookmark.timestamp }) {
            scrollToSegmentID = match.id
            return
        }
        if let first = sorted.first {
            scrollToSegmentID = first.id
        }
    }
}
