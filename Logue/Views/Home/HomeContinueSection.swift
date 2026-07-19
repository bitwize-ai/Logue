import SwiftUI

/// "Continue Where You Left Off" — horizontal scroll of recently modified items with Space breadcrumbs.
struct HomeContinueSection: View {
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore

    var body: some View {
        let items = recentItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardSectionHeader(icon: "arrow.uturn.forward", title: "Continue Where You Left Off")
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { item in
                            continueCard(item)
                                .frame(width: 220)
                                .accessibilityLabel(item.title)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Card

    private func continueCard(_ item: RecentActivityItem) -> some View {
        HomeCardShell {
            switch item {
            case let .meeting(note): meetingStore.selectedMeetingID = note.id
            case let .document(doc): documentStore.selectedDocumentID = doc.id
            }
        } content: { _ in
            VStack(alignment: .leading, spacing: 8) {
                // Icon + type indicator
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.caption)
                        .foregroundStyle(item.iconColor)
                    Spacer()
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(AppThemeConstants.pinnedColor)
                    }
                }

                // Title
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Preview
                Text(previewText(for: item))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                // Space breadcrumb + time
                VStack(alignment: .leading, spacing: 4) {
                    if let breadcrumb = spaceBreadcrumb(for: item) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 8))
                            Text(breadcrumb)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                    HStack {
                        Text(metadataText(for: item))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(item.date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        } contextMenu: {
            EmptyView()
        }
    }

    // MARK: - Data

    private var recentItems: [RecentActivityItem] {
        let meetings: [RecentActivityItem] = meetingStore.activeMeetings
            .filter { !$0.isArchived }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(5)
            .map { .meeting($0) }
        let docs: [RecentActivityItem] = documentStore.activeDocuments
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(5)
            .map { .document($0) }
        return Array((meetings + docs).sorted { $0.date > $1.date }.prefix(5))
    }

    private func previewText(for item: RecentActivityItem) -> String {
        switch item {
        case let .meeting(note):
            if let summary = note.summary {
                return summary
            }
            if !note.segments.isEmpty {
                return note.segments.prefix(5).map(\.text).joined(separator: " ")
            }
            return "No transcript yet"
        case let .document(doc):
            return doc.snippet.isEmpty ? "Empty document" : doc.snippet
        }
    }

    private func metadataText(for item: RecentActivityItem) -> String {
        switch item {
        case let .meeting(note):
            note.duration > 0 ? note.formattedDuration : ""
        case let .document(doc):
            "\(doc.wordCount)w"
        }
    }

    private func spaceBreadcrumb(for item: RecentActivityItem) -> String? {
        let spaceID: UUID? = switch item {
        case let .meeting(note): note.spaceID
        case let .document(doc): doc.spaceID
        }
        guard let spaceID else { return nil }
        let path = spaceStore.path(to: spaceID)
        guard !path.isEmpty else { return nil }
        return path.map(\.name).joined(separator: " > ")
    }
}
