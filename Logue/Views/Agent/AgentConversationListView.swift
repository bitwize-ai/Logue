import AppKit
import SwiftUI

/// Popover or sheet view listing past agent conversations.
///
/// Phase A0 polish:
///   • Conversations grouped by Today / Yesterday / Last 7 days / Last 30 days / Older.
///   • Pinned section pinned to the top.
///   • Inline rename on double-click.
///   • Archive (soft-delete with 30-day recovery) is the default destructive action.
///   • Hard delete only available inside the Archived view.
///   • ⌘E / right-click → Export as Markdown to ~/Downloads.
struct AgentConversationListView: View {
    @State private var conversationStore = AgentConversationStore.shared
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var renamingID: UUID?
    @State private var renameDraft = ""
    var onSelect: (UUID) -> Void

    private var visibleConversations: [AgentConversation] {
        let pool = conversationStore.conversations.filter { $0.isArchived == showArchived }
        guard !searchText.isEmpty else { return pool }
        let query = searchText.lowercased()
        return pool.filter { conv in
            conv.title.lowercased().contains(query)
                || conv.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            content
            archivedToggleFooter
        }
        .frame(minWidth: 280, minHeight: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(showArchived ? "Archived" : "Conversations")
                .font(.headline)
            Spacer()
            if !showArchived {
                Button {
                    let conv = conversationStore.createConversation()
                    onSelect(conv.id)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Search conversations…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if visibleConversations.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            List {
                // Pinned bucket — only in the active (non-archived) view.
                if !showArchived {
                    let pinned = visibleConversations.filter(\.isPinned)
                    if !pinned.isEmpty {
                        Section("Pinned") {
                            ForEach(pinned) { conv in conversationRow(conv) }
                        }
                    }
                }

                // Date-grouped sections (Today / Yesterday / …).
                let groups = bucketByDate(visibleConversations.filter { !$0.isPinned || showArchived })
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.conversations) { conv in conversationRow(conv) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No matches"
        }
        return showArchived ? "No archived conversations" : "No conversations yet"
    }

    // MARK: - Footer (Archived toggle)

    private var archivedToggleFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showArchived.toggle()
                renamingID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArchived ? "tray.full" : "archivebox")
                        .font(.caption)
                    Text(showArchived ? "Active conversations" : "Archived")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func conversationRow(_ conversation: AgentConversation) -> some View {
        if renamingID == conversation.id {
            renameRow(conversation)
        } else {
            Button {
                onSelect(conversation.id)
            } label: {
                rowBody(conversation)
            }
            .buttonStyle(.plain)
            .contextMenu { contextMenu(for: conversation) }
            .onTapGesture(count: 2) {
                renamingID = conversation.id
                renameDraft = conversation.title
            }
        }
    }

    private func rowBody(_ conversation: AgentConversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(conversation.messages.count) messages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(conversation.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func renameRow(_ conversation: AgentConversation) -> some View {
        HStack(spacing: 6) {
            TextField("Conversation title", text: $renameDraft, onCommit: {
                commitRename(conversation: conversation)
            })
            .textFieldStyle(.plain)
            .font(.callout.weight(.medium))
            .onSubmit { commitRename(conversation: conversation) }
            .onExitCommand { renamingID = nil }

            Button {
                commitRename(conversation: conversation)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitRename(conversation: AgentConversation) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != conversation.title {
            conversationStore.updateTitle(trimmed, for: conversation.id)
            ToastCenter.shared.show(UICopy.Toast.saved)
        }
        renamingID = nil
    }

    @ViewBuilder
    private func contextMenu(for conversation: AgentConversation) -> some View {
        Button(conversation.isPinned ? UICopy.Action.unpin : UICopy.Action.pin) {
            conversationStore.togglePin(for: conversation.id)
            ToastCenter.shared.show(conversation.isPinned ? UICopy.Toast.unpinned : UICopy.Toast.pinned)
        }
        Button(UICopy.Action.rename) {
            renamingID = conversation.id
            renameDraft = conversation.title
        }
        Divider()
        Button(UICopy.Action.exportConversation) {
            exportConversation(conversation)
        }
        Divider()
        if conversation.isArchived {
            Button(UICopy.Action.restore) {
                conversationStore.unarchiveConversation(conversation.id)
                ToastCenter.shared.show(UICopy.Toast.restored)
            }
            Button(UICopy.Action.delete, role: .destructive) {
                conversationStore.deleteConversation(conversation.id)
            }
        } else {
            Button(UICopy.Action.archive) {
                conversationStore.archiveConversation(conversation.id)
                ToastCenter.shared.show(UICopy.Toast.archived)
            }
        }
    }

    // MARK: - Export

    private func exportConversation(_ conversation: AgentConversation) {
        guard let url = conversationStore.exportMarkdownToDownloads(for: conversation.id) else { return }
        ToastCenter.shared.show(UICopy.Toast.exported)
        // Reveal in Finder so the user knows where it landed.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Date grouping

    private struct DateGroup {
        let title: String
        let conversations: [AgentConversation]
    }

    /// Bucket conversations by recency relative to "now". Order is
    /// preserved within a bucket — the store already sorts by modifiedAt.
    private func bucketByDate(_ items: [AgentConversation]) -> [DateGroup] {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.startOfDay(for: now.addingTimeInterval(-24 * 3600))
        let last7 = cal.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600))
        let last30 = cal.startOfDay(for: now.addingTimeInterval(-30 * 24 * 3600))

        var today: [AgentConversation] = []
        var yest: [AgentConversation] = []
        var week: [AgentConversation] = []
        var month: [AgentConversation] = []
        var older: [AgentConversation] = []

        for conv in items {
            let day = cal.startOfDay(for: conv.modifiedAt)
            if cal.isDateInToday(conv.modifiedAt) {
                today.append(conv)
            } else if day == yesterday {
                yest.append(conv)
            } else if day >= last7 {
                week.append(conv)
            } else if day >= last30 {
                month.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [DateGroup] = []
        if !today.isEmpty {
            groups.append(.init(title: "Today", conversations: today))
        }
        if !yest.isEmpty {
            groups.append(.init(title: "Yesterday", conversations: yest))
        }
        if !week.isEmpty {
            groups.append(.init(title: "Last 7 days", conversations: week))
        }
        if !month.isEmpty {
            groups.append(.init(title: "Last 30 days", conversations: month))
        }
        if !older.isEmpty {
            groups.append(.init(title: "Older", conversations: older))
        }
        return groups
    }
}
