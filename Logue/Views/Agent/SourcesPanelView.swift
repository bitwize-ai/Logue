import AppKit
import SwiftUI

/// Phase B: collapsible panel attached to the right side of `AgentChatView`
/// that surfaces what the agent is currently working with — active
/// attachments, deduplicated cited URLs from web tools, and referenced
/// meetings/documents this conversation has touched.
struct SourcesPanelView: View {
    let conversationID: UUID?
    @Binding var attachments: [TempAttachment]
    @State private var store = AgentConversationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !attachments.isEmpty {
                        section("Attachments", systemImage: "paperclip") {
                            attachmentsRows
                        }
                    }
                    if !citedURLs.isEmpty {
                        section("Recent sources", systemImage: "globe") {
                            urlRows
                        }
                    }
                    if !referencedItems.isEmpty {
                        section("Referenced", systemImage: "doc.text") {
                            referencedRows
                        }
                    }
                    if isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 280)
        .background(Color.secondary.opacity(0.04))
        .overlay(alignment: .leading) {
            Divider()
        }
    }

    // MARK: - Components

    private var header: some View {
        HStack(spacing: 6) {
            Text("Sources")
                .font(.callout.weight(.semibold))
            Spacer()
            Text("\(citedURLs.count + attachments.count + referencedItems.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func section(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            content()
        }
    }

    private var attachmentsRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .frame(width: 16)
                        .foregroundStyle(Color.accentColor)
                    Text(item.displayName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if idx < attachments.count {
                            attachments.remove(at: idx)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
    }

    private var urlRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(citedURLs, id: \.absoluteString) { url in
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 6) {
                        FaviconView(url: url)
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.host ?? url.absoluteString)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(Color.primary)
                            Text(url.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var referencedRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(referencedItems, id: \.id) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(item.label)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sources yet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Drop a file or ask the agent to search the web.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Derived state

    private var conversation: AgentConversation? {
        guard let conversationID else { return nil }
        return store.conversations.first { $0.id == conversationID }
    }

    private var citedURLs: [URL] {
        guard let conversation else { return [] }
        var urls: [URL] = []
        var seen = Set<String>()
        let urlPattern = try? NSRegularExpression(
            pattern: #"https?://[^\s\)\]\"'<>]+"#,
            options: []
        )
        for msg in conversation.messages {
            // Look at tool results for web tools — these are the canonical citations.
            if let result = msg.toolResult {
                let text = result.output
                guard let regex = urlPattern else { continue }
                let range = NSRange(text.startIndex..., in: text)
                regex.enumerateMatches(in: text, range: range) { match, _, _ in
                    guard let hit = match,
                          let hitRange = Range(hit.range, in: text)
                    else { return }
                    let raw = String(text[hitRange])
                    let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)"))
                    guard let url = URL(string: cleaned),
                          let host = url.host,
                          !host.isEmpty,
                          !seen.contains(url.absoluteString)
                    else { return }
                    seen.insert(url.absoluteString)
                    urls.append(url)
                }
            }
        }
        return Array(urls.prefix(10))
    }

    private struct ReferencedItem {
        let id: String
        let icon: String
        let label: String
    }

    private var referencedItems: [ReferencedItem] {
        guard let conversation else { return [] }
        var items: [ReferencedItem] = []
        var seen = Set<String>()
        for msg in conversation.messages {
            for call in msg.toolCalls {
                let name = call.toolName
                guard name.contains("meeting") || name.contains("document") else { continue }
                let raw = call.arguments
                let key = "\(name):\(raw)"
                guard !seen.contains(key), !raw.isEmpty else { continue }
                seen.insert(key)
                items.append(ReferencedItem(
                    id: key,
                    icon: name.contains("meeting") ? "person.2.fill" : "doc.text",
                    label: prettyLabel(toolName: name, arguments: raw)
                ))
            }
        }
        return Array(items.prefix(8))
    }

    private var isEmpty: Bool {
        attachments.isEmpty && citedURLs.isEmpty && referencedItems.isEmpty
    }

    private func prettyLabel(toolName: String, arguments: String) -> String {
        // Try to extract a "title" or "id" field from the JSON-encoded args
        // string. Falls back to the tool name when nothing meaningful is found.
        if let data = arguments.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            for key in ["title", "name", "query", "id"] {
                if let value = dict[key] as? String, !value.isEmpty {
                    return "\(toolName): \(String(value.prefix(40)))"
                }
            }
        }
        return toolName
    }
}

// MARK: - Favicon helper

private struct FaviconView: View {
    let url: URL
    @State private var cache = FaviconCache.shared

    var body: some View {
        if let img = cache.cached(for: url) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tertiary)
                .onAppear { cache.prefetch(for: url) }
        }
    }
}
