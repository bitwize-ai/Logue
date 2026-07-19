import SwiftUI

/// Browse, edit, and delete the agent's auto-extracted user memories.
/// Mirrors the look of `AgentConversationListView` for consistency.
struct MemoryListView: View {
    @State private var memories: [UserMemory] = []
    @State private var searchText = ""
    @State private var editingID: UUID?
    @State private var draftText: String = ""
    @State private var isLoading = true
    @State private var showClearConfirm = false

    private var filteredMemories: [UserMemory] {
        guard !searchText.isEmpty else { return memories }
        let query = searchText.lowercased()
        return memories.filter { $0.text.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            content
        }
        .frame(minWidth: 320, minHeight: 360)
        .task { await reload() }
        .alert("Clear all memories?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await MemoryStore.shared.clearAll()
                    await reload()
                }
            }
        } message: {
            Text("This deletes everything Logue has remembered about you across conversations. The agent will start with a clean slate.")
        }
    }

    private var header: some View {
        HStack {
            Text("Memories")
                .font(.headline)
            Spacer()
            if !memories.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("Clear all memories")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if memories.isEmpty {
            emptyState
        } else if filteredMemories.isEmpty {
            VStack {
                Spacer()
                Text("No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(filteredMemories) { memory in
                    memoryRow(memory)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No memories yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Logue will remember persistent facts you share — your role, preferences, ongoing projects — across conversations.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    @ViewBuilder
    private func memoryRow(_ memory: UserMemory) -> some View {
        if editingID == memory.id {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $draftText)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") {
                        editingID = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Save") {
                        Task {
                            await MemoryStore.shared.updateMemory(id: memory.id, newText: draftText)
                            editingID = nil
                            await reload()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(memory.text)
                    .font(.callout)
                    .lineLimit(3)
                Text(memory.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Edit") {
                    draftText = memory.text
                    editingID = memory.id
                }
                Divider()
                Button("Delete", role: .destructive) {
                    Task {
                        await MemoryStore.shared.deleteMemory(id: memory.id)
                        await reload()
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func reload() async {
        let loaded = await MemoryStore.shared.allMemories()
        memories = loaded
        isLoading = false
    }
}
