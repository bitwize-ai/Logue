import Foundation

/// One persistent fact the agent has learned about the user across conversations.
/// Auto-extracted by the worker prompt in `PromptRegistry.Memory.extraction`, then
/// embedded and stored via `MemoryStore` + `VectorStore` (namespace `"memory"`).
///
/// Format invariant: `text` always begins with "The user " — matches Sidekick's
/// extraction grammar so the LLM can ingest the recall block uniformly.
struct UserMemory: Identifiable, Codable {
    let id: UUID
    /// The memory body (e.g. "The user is a Swift developer working on macOS apps").
    var text: String
    /// The user message this memory was extracted from. Optional because user-edited
    /// memories may have no canonical source message.
    let sourceMessageID: UUID?
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = .init(),
        text: String,
        sourceMessageID: UUID? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.sourceMessageID = sourceMessageID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text, sourceMessageID, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        sourceMessageID = try container.decodeIfPresent(UUID.self, forKey: .sourceMessageID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .now
    }
}
