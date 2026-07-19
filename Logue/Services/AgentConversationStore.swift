import Foundation
import os.log

/// Manages persistence of agent conversations using encrypted JSON files.
/// Follows the same pattern as `MeetingStore` and `DocumentStore` — encrypted via
/// `EncryptionManager`, @MainActor @Observable for SwiftUI binding, and O(1) lookups.
@MainActor @Observable
final class AgentConversationStore {
    static let shared = AgentConversationStore()

    private(set) var conversations: [AgentConversation] = []
    var selectedConversationID: UUID?

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "AgentConversationStore")

    /// Maximum stored conversations before oldest are pruned.
    private static let maxConversations = 100

    /// Directory for agent conversation files.
    private static var storageDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "Logue/agent_conversations", directoryHint: .isDirectory)
    }

    private init() {
        loadAll()
    }

    // MARK: - CRUD

    /// Creates a new conversation and selects it.
    @discardableResult
    func createConversation(title: String = "New Conversation") -> AgentConversation {
        let conversation = AgentConversation(title: title)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        save(conversation)
        pruneIfNeeded()
        return conversation
    }

    /// Returns the currently selected conversation, or nil.
    var selectedConversation: AgentConversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    /// Appends a message to a conversation and persists.
    func appendMessage(_ message: AgentMessage, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            logger.warning("Cannot append message: conversation \(conversationID.uuidString) not found")
            return
        }
        conversations[index].messages.append(message)
        conversations[index].modifiedAt = .now
        save(conversations[index])
    }

    /// Updates the last assistant message content (for streaming token appends).
    func updateLastAssistantMessage(in conversationID: UUID, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard let msgIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[index].messages[msgIndex].content = content
        conversations[index].modifiedAt = .now
    }

    /// Removes the last assistant message (e.g. streaming placeholder when tool calls are detected).
    func removeLastAssistantMessage(from conversationID: UUID) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        if let lastIdx = conversations[convIndex].messages.lastIndex(where: { $0.role == .assistant }) {
            conversations[convIndex].messages.remove(at: lastIdx)
        }
    }

    /// Updates the body of an existing user message. Used when the user edits a previous
    /// question and re-sends it.
    func updateUserMessageContent(messageID: UUID, in conversationID: UUID, content: String) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageID }),
              conversations[convIndex].messages[msgIndex].role == .user
        else { return }
        conversations[convIndex].messages[msgIndex].content = content
        conversations[convIndex].modifiedAt = .now
        save(conversations[convIndex])
    }

    /// Removes every message that follows `messageID` (the anchor message itself is kept).
    /// Used to regenerate the assistant response from an edited user question.
    func truncateMessagesAfter(messageID: UUID, in conversationID: UUID) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let keep = msgIndex + 1
        guard keep < conversations[convIndex].messages.count else { return }
        conversations[convIndex].messages = Array(conversations[convIndex].messages.prefix(keep))
        conversations[convIndex].modifiedAt = .now
        save(conversations[convIndex])
    }

    /// Updates the status of a specific tool call within a message.
    func updateToolCallStatus(
        in conversationID: UUID,
        messageID: UUID,
        toolCallID: UUID,
        status: AgentToolCallStatus
    ) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        guard let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard let callIndex = conversations[convIndex].messages[msgIndex].toolCalls
            .firstIndex(where: { $0.id == toolCallID })
        else { return }
        conversations[convIndex].messages[msgIndex].toolCalls[callIndex].status = status
    }

    /// Updates the conversation title (e.g. auto-generated from first user message).
    func updateTitle(_ title: String, for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].title = title
        conversations[index].modifiedAt = .now
        save(conversations[index])
    }

    /// Toggles pin state for a conversation.
    func togglePin(for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isPinned.toggle()
        conversations[index].modifiedAt = .now
        save(conversations[index])
    }

    /// Phase A0: archives a conversation (soft delete) instead of removing it.
    /// Archived conversations live in the "Archived" view for 30 days, then
    /// the cleanup pass purges them. Use `unarchive` to restore.
    func archiveConversation(_ conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isArchived = true
        conversations[index].archivedAt = .now
        conversations[index].modifiedAt = .now
        if selectedConversationID == conversationID {
            selectedConversationID = conversations.first { !$0.isArchived }?.id
        }
        save(conversations[index])
    }

    /// Phase A0: restores an archived conversation. Clears `archivedAt`.
    func unarchiveConversation(_ conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].isArchived = false
        conversations[index].archivedAt = nil
        conversations[index].modifiedAt = .now
        save(conversations[index])
    }

    /// Phase A0: purges any conversations archived more than 30 days ago.
    /// Call from the store's init or periodically — destructive, no undo.
    func purgeStaleArchives(now: Date = .now, ttlDays: Int = 30) {
        let cutoff = now.addingTimeInterval(-Double(ttlDays) * 24 * 3600)
        let stale = conversations.filter { $0.isArchived && ($0.archivedAt ?? .distantFuture) < cutoff }
        for conv in stale {
            deleteConversation(conv.id)
        }
    }

    /// Deletes a conversation permanently. Prefer `archiveConversation` as the
    /// default destructive action — only call `delete` from the Archived view.
    func deleteConversation(_ conversationID: UUID) {
        conversations.removeAll { $0.id == conversationID }
        if selectedConversationID == conversationID {
            selectedConversationID = conversations.first?.id
        }
        let fileURL = Self.storageDirectory.appending(path: "\(conversationID.uuidString).json")
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Failed to delete conversation file: \(error.localizedDescription)")
        }
    }

    // MARK: - Phase A0: Export

    /// Render a conversation as plain Markdown. Includes the title, message
    /// timestamps, and a "user:" / "assistant:" speaker prefix on each turn.
    /// Tool-call/result rows are rendered as code-fenced blocks so the
    /// exported Markdown is round-trippable.
    func exportMarkdown(for conversationID: UUID) -> String? {
        guard let conv = conversations.first(where: { $0.id == conversationID }) else { return nil }
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .short
        var out = "# \(conv.title)\n\n"
        out += "_\(dateFmt.string(from: conv.createdAt)) — \(dateFmt.string(from: conv.modifiedAt))_\n\n"
        for msg in conv.messages {
            switch msg.role {
            case .user:
                out += "## You\n\n\(msg.content)\n\n"
            case .assistant:
                out += "## Logue\n\n\(msg.content)\n\n"
            case .toolCall:
                for call in msg.toolCalls {
                    out += "_called `\(call.toolName)`_\n\n"
                }
            case .toolResult:
                if let result = msg.toolResult {
                    out += "```\n\(result.output.prefix(2000))\n```\n\n"
                }
            }
        }
        return out
    }

    /// Writes the conversation as Markdown into ~/Downloads. Returns the URL
    /// on success so the caller can show a "Saved" toast with click-through.
    @discardableResult
    func exportMarkdownToDownloads(for conversationID: UUID) -> URL? {
        guard let body = exportMarkdown(for: conversationID),
              let conv = conversations.first(where: { $0.id == conversationID })
        else { return nil }
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let safeTitle = conv.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(80)
        let url = downloads.appending(path: "\(safeTitle).md")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            logger.error("Failed to export conversation: \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists a specific conversation after changes (debounced per-conversation saves
    /// are not needed — agent conversations are small and saved infrequently).
    func persistConversation(_ conversationID: UUID) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        save(conversation)
    }

    // MARK: - Persistence

    private func loadAll() {
        let dir = Self.storageDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create agent conversations directory: \(error.localizedDescription)")
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            var loaded: [AgentConversation] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let conversation = try EncryptionManager.decryptCodable(AgentConversation.self, from: data)
                    loaded.append(conversation)
                } catch {
                    // Try unencrypted fallback for development data
                    do {
                        let data = try Data(contentsOf: file)
                        let conversation = try JSONDecoder().decode(AgentConversation.self, from: data)
                        loaded.append(conversation)
                    } catch {
                        logger.error("Failed to load conversation from \(file.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }

            // Sort: pinned first, then by modified date descending
            conversations = loaded.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.modifiedAt > rhs.modifiedAt
            }
        } catch {
            logger.error("Failed to list agent conversation files: \(error.localizedDescription)")
        }
    }

    private func save(_ conversation: AgentConversation) {
        let dir = Self.storageDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create directory for save: \(error.localizedDescription)")
            return
        }

        let fileURL = dir.appending(path: "\(conversation.id.uuidString).json")
        do {
            let data = try EncryptionManager.encryptCodable(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save conversation \(conversation.id.uuidString): \(error.localizedDescription)")
        }
    }

    /// Removes oldest non-pinned conversations when over the limit.
    private func pruneIfNeeded() {
        let unpinned = conversations.filter { !$0.isPinned }
        guard unpinned.count > Self.maxConversations else { return }

        let toRemove = unpinned
            .sorted { $0.modifiedAt < $1.modifiedAt }
            .prefix(unpinned.count - Self.maxConversations)

        for conversation in toRemove {
            deleteConversation(conversation.id)
        }
    }
}
