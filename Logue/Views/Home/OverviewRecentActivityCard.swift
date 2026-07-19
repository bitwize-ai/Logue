import SwiftUI

// MARK: - Recent Activity Item

enum RecentActivityItem: Identifiable {
    case meeting(MeetingNote)
    case document(WritingDocument)

    var id: UUID {
        switch self {
        case let .meeting(note): note.id
        case let .document(doc): doc.id
        }
    }

    var date: Date {
        switch self {
        case let .meeting(note): note.modifiedAt
        case let .document(doc): doc.modifiedAt
        }
    }

    var title: String {
        switch self {
        case let .meeting(note): note.title
        case let .document(doc): doc.title
        }
    }

    var icon: String {
        switch self {
        case let .meeting(note): note.recordingMode.iconName
        case .document: "doc.text"
        }
    }

    var iconColor: Color {
        switch self {
        case .meeting: AppThemeConstants.accent
        case .document: AppThemeConstants.categoryPurple
        }
    }

    var isPinned: Bool {
        switch self {
        case let .meeting(note): note.isPinned
        case let .document(doc): doc.isPinned
        }
    }

    var subtitle: String {
        switch self {
        case let .meeting(note):
            var parts = [note.createdAt.formatted(.relative(presentation: .named))]
            if note.duration > 0 {
                parts.append(note.formattedDuration)
            }
            return parts.joined(separator: " \u{2022} ")
        case let .document(doc):
            return doc.modifiedAt.formatted(.relative(presentation: .named))
        }
    }
}

// MARK: - Recent Activity Card

/// Card showing recent meetings and documents, sorted by modification date.
struct OverviewRecentActivityCard: View {
    let meetingStore: MeetingStore
    let documentStore: DocumentStore

    var body: some View {
        InsightCardShell {
            VStack(alignment: .leading, spacing: 14) {
                CardSectionHeader(icon: "clock.arrow.circlepath", title: "Recent Activity")
                let items = recentItems
                if items.isEmpty {
                    Text("No recent activity")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            recentItemRow(item)
                            if item.id != items.last?.id {
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                }
            }
        }
    }

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
        return Array((meetings + docs).sorted { $0.date > $1.date }.prefix(7))
    }

    private func recentItemRow(_ item: RecentActivityItem) -> some View {
        Button {
            switch item {
            case let .meeting(note): meetingStore.selectedMeetingID = note.id
            case let .document(doc): documentStore.selectedDocumentID = doc.id
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.caption)
                    .foregroundStyle(item.iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(AppThemeConstants.pinnedColor)
                        .accessibilityLabel("Favorited")
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint("Opens \(item.title)")
    }
}
