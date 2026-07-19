import Foundation

// MARK: - AgentConversation

/// A conversation session with the agentic AI assistant.
/// Persists across app launches via encrypted JSON (matching MeetingStore pattern).
struct AgentConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [AgentMessage]
    let createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    /// Phase A0: archived conversations live in a separate "Archived" view for
    /// 30 days before being purged. Default destructive action prefers archive
    /// over hard delete so users can recover an accidental swipe.
    var isArchived: Bool
    /// Phase A0: when archived, this records the archive date so the cleanup
    /// job (purge after 30 days) has a stable reference. Nil when unarchived.
    var archivedAt: Date?

    init(
        id: UUID = .init(),
        title: String = "New Conversation",
        messages: [AgentMessage] = [],
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        isPinned: Bool = false,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }

    // Codable: use decodeIfPresent with defaults for forward compatibility.
    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, modifiedAt, isPinned, isArchived, archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New Conversation"
        messages = try container.decodeIfPresent([AgentMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .now
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

// MARK: - AgentMessage

/// A single message in an agent conversation (user, assistant, tool call, or tool result).
struct AgentMessage: Identifiable, Codable {
    let id: UUID
    let role: AgentMessageRole
    var content: String
    var toolCalls: [AgentToolCall]
    var toolResult: AgentToolResult?
    /// Drag-and-drop attachments captured at submission time. Persisted with the
    /// message so a re-loaded conversation still shows what the user dropped.
    var attachments: [TempAttachment]
    let timestamp: Date

    init(
        id: UUID = .init(),
        role: AgentMessageRole,
        content: String,
        toolCalls: [AgentToolCall] = [],
        toolResult: AgentToolResult? = nil,
        attachments: [TempAttachment] = [],
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResult = toolResult
        self.attachments = attachments
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, toolCalls, toolResult, attachments, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AgentMessageRole.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        toolCalls = try container.decodeIfPresent([AgentToolCall].self, forKey: .toolCalls) ?? []
        toolResult = try container.decodeIfPresent(AgentToolResult.self, forKey: .toolResult)
        attachments = try container.decodeIfPresent([TempAttachment].self, forKey: .attachments) ?? []
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? .now
    }
}

// MARK: - AgentMessageRole

enum AgentMessageRole: String, Codable {
    case user
    case assistant
    case toolCall
    case toolResult
}

// MARK: - AgentToolCall

/// A tool invocation requested by the LLM during an agent loop iteration.
struct AgentToolCall: Identifiable, Codable {
    let id: UUID
    let toolName: String
    /// JSON-encoded arguments string (kept as String for Codable simplicity).
    let arguments: String
    var status: AgentToolCallStatus
    /// Permission tier captured at request time. Used by the approval card to choose
    /// the right UI variant (plain Approve vs Touch ID-required Approve).
    /// Defaults to `.regular` for backwards compatibility with conversations persisted
    /// before clearance was added.
    var clearance: ToolClearance

    init(
        id: UUID = .init(),
        toolName: String,
        arguments: String,
        status: AgentToolCallStatus = .pending,
        clearance: ToolClearance = .regular
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.status = status
        self.clearance = clearance
    }

    enum CodingKeys: String, CodingKey {
        case id, toolName, arguments, status, clearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        toolName = try container.decode(String.self, forKey: .toolName)
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? "{}"
        status = try container.decodeIfPresent(AgentToolCallStatus.self, forKey: .status) ?? .pending
        clearance = try container.decodeIfPresent(ToolClearance.self, forKey: .clearance) ?? .regular
    }

    /// Convenience: parse arguments back to a dictionary for tool execution.
    func parsedArguments() -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}

// MARK: - AgentToolCallStatus

enum AgentToolCallStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case needsConfirmation
}

// MARK: - AgentToolResult

/// The output of a tool execution, fed back into the agent loop.
struct AgentToolResult: Codable {
    let toolCallID: UUID
    let output: String
    let isError: Bool

    init(toolCallID: UUID, output: String, isError: Bool = false) {
        self.toolCallID = toolCallID
        self.output = output
        self.isError = isError
    }
}
