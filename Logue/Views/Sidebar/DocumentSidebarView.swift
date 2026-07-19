import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case all = "All Documents"
    case recent = "Recent"
    case pinned = "Pinned"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .all: "doc.text"
        case .recent: "clock"
        case .pinned: "pin"
        }
    }
}

/// Primary sidebar: branding, home button, new doc, search, section pills, and document list.
struct DocumentSidebarView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""
    @State private var activeSection: SidebarSection = .all

    private var filteredDocs: [WritingDocument] {
        let base: [WritingDocument] = switch activeSection {
        case .all: store.activeDocuments
        case .recent: store.recentDocuments
        case .pinned: store.pinnedDocuments
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            searchBar
            Divider()
            sectionPills
            Divider()
            documentList
            Divider()
            sidebarFooter
        }
        .background(AppThemeConstants.chromeBackground)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            // Home button
            Button {
                store.selectedDocumentID = nil
                meetingStore.selectedMeetingID = nil
            } label: {
                Image(systemName: "house")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Home")
            .accessibilityHint("Returns to the home screen")
            .help("Home")

            Spacer()

            Button {
                store.createDocument()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Document")
            .accessibilityHint("Creates a new blank document")
            .help("New Document")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .accessibilityLabel("Search documents")
                .accessibilityHint("Type to filter the document list")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clears the search text")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Section Pills

    private var sectionPills: some View {
        HStack(spacing: 0) {
            ForEach(SidebarSection.allCases) { section in
                SectionPillButton(
                    section: section,
                    isActive: activeSection == section,
                    action: { activeSection = section }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Document List

    @ViewBuilder
    private var documentList: some View {
        if filteredDocs.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Documents" : "No Results",
                systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass"
            )
            .font(.callout)
            .frame(maxHeight: .infinity)
        } else {
            List(filteredDocs, selection: Binding(
                get: { store.selectedDocumentID },
                set: { store.selectedDocumentID = $0 }
            )) { doc in
                DocumentListRow(document: doc)
                    .tag(doc.id)
                    .accessibilityLabel("\(doc.title)\(doc.isPinned ? ", pinned" : "")")
                    .accessibilityHint("Opens this document")
                    .contextMenu { docContextMenu(for: doc) }
            }
            .listStyle(.sidebar)
            .tint(AppThemeConstants.accent)
        }
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack {
            Button(action: { openSettings() }, label: {
                Label("Settings", systemImage: "gear")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens application settings")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        Divider()
        Button(role: .destructive) {
            store.deleteDocument(id: doc.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

// MARK: - Section Pill Button

private struct SectionPillButton: View {
    let section: SidebarSection
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: section.icon)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(isActive ? AppThemeConstants.accent : Color.secondary)
                .background(
                    isActive ? AppThemeConstants.accent.opacity(AppThemeConstants.activeOpacity) : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusSmall)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityHint("Filters to show \(section.rawValue.lowercased())")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(section.rawValue)
    }
}

// MARK: - Document List Row

struct DocumentListRow: View {
    let document: WritingDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if document.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(AppThemeConstants.pinnedColor)
                }
                if let score = document.score {
                    Text("\(Int(score.overall))")
                        .font(.caption2.bold())
                        .foregroundStyle(scoreColor(score.overall))
                }
            }
            Text(document.snippet.isEmpty ? "Empty document" : document.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Text(document.readingTimeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(document.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Double) -> Color {
        score >= 85 ? AppThemeConstants.success : score >= 70 ? AppThemeConstants.warning : AppThemeConstants.error
    }
}
