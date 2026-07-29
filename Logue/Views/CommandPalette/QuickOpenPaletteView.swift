import SwiftUI

/// Jump straight to a document or meeting by name — `Cmd+P` / `Cmd+O`.
///
/// A separate surface from `CommandPaletteView` rather than a mode inside it, because the two
/// answer different questions and are shaped differently for it. The command palette groups
/// results by category and runs a debounced full-text search over bodies and transcripts;
/// quick-open is a single flat list, ranked by title only, filtered synchronously on every
/// keystroke. Sharing one view would have meant a mode flag threaded through the grouping,
/// the debounce and the keyboard handling alike.
///
/// All ranking is `QuickOpenMatcher`'s — there is no second matching implementation here.
struct QuickOpenPaletteView: View {
    @Binding var isPresented: Bool

    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    /// Documents and meetings, most recently modified first.
    ///
    /// The order matters: `QuickOpenMatcher` is stable within a rank, so the caller's ordering
    /// is what breaks ties — recency, here. Trashed items are excluded by `activeDocuments`
    /// and `activeMeetings`.
    private var candidates: [QuickOpenItem] {
        let documents = documentStore.activeDocuments.map {
            (modifiedAt: $0.modifiedAt, item: QuickOpenItem(
                id: $0.id,
                title: $0.title.isEmpty ? AppConstants.defaultDocumentTitle : $0.title,
                kind: .document
            ))
        }
        let meetings = meetingStore.activeMeetings.map {
            (modifiedAt: $0.modifiedAt, item: QuickOpenItem(
                id: $0.id,
                title: $0.title.isEmpty ? AppConstants.defaultMeetingTitle : $0.title,
                kind: .meeting
            ))
        }
        return (documents + meetings)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map(\.item)
    }

    private var results: [QuickOpenItem] {
        QuickOpenMatcher.match(query: query, in: candidates)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            if results.isEmpty {
                emptyState
            } else {
                resultList
            }

            Divider()
            HStack(spacing: 16) {
                footerHint(icon: "arrow.up.arrow.down", text: "Navigate")
                footerHint(icon: "return", text: "Open")
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
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.doc.on.clipboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Go to document or meeting…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .accessibilityLabel("Quick open search")
                .accessibilityHint("Type part of a document or meeting title")
                .onSubmit { openSelected() }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clears the quick open search text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(candidates.isEmpty ? "Nothing to open yet" : "No matches for \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        QuickOpenRow(item: item, isSelected: index == selectedIndex) {
                            open(item)
                        }
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)
            .onChange(of: selectedIndex) { _, newIndex in
                // Bounds-checked because the result set shrinks as the query grows, and the
                // index can be stale for a frame after a keystroke.
                guard newIndex >= 0, newIndex < results.count else { return }
                proxy.scrollTo(results[newIndex].id)
            }
        }
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

    // MARK: - Opening

    private func openSelected() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        open(results[selectedIndex])
    }

    /// Selecting an item opens it: `MainWindowView` observes both stores' selection and
    /// switches to the editor or the meeting workspace, so setting the ID is the whole action.
    private func open(_ item: QuickOpenItem) {
        isPresented = false
        switch item.kind {
        case .document:
            meetingStore.selectedMeetingID = nil
            documentStore.selectedDocumentID = item.id
        case .meeting:
            documentStore.selectedDocumentID = nil
            meetingStore.selectedMeetingID = item.id
        }
    }
}

// MARK: - Row

private struct QuickOpenRow: View {
    let item: QuickOpenItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var kindLabel: String {
        switch item.kind {
        case .document: "Document"
        case .meeting: "Meeting"
        }
    }

    private var kindIcon: String {
        switch item.kind {
        case .document: "doc.text"
        case .meeting: "waveform"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: kindIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 24, height: 24)

                Text(item.title)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.opacityMedium)
                        : (isHovered ? Color.primary.opacity(AppThemeConstants.opacityLight) : Color.clear))
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(item.title), \(kindLabel)")
        .accessibilityHint("Opens this \(kindLabel.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
