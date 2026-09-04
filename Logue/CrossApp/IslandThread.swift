import Foundation

/// Why the island is putting itself away.
///
/// The view knows the difference; the controller only knows a closure fired. Without this
/// the dismissal log attributed "Open in Logue" to the close button, which is the one thing
/// the log exists to tell apart.
enum CommandCenterChatDismissal: Equatable {
    case closeButton
    case openInLogue
}

/// One turn as the island draws it.
///
/// Named for what it was — a view model over messages the island kept in its own array and
/// threw away on dismiss. It now reads from the store like everything else; the name stayed
/// because renaming it touches every bubble and buys nothing.
struct EphemeralChatMessage: Identifiable, Equatable {
    let id: UUID
    var content: String
    let isUser: Bool
    var isStreaming: Bool
    let timestamp: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
    }
}

/// A single row in the island, which is either something someone said or something the agent
/// did.
enum IslandRow: Identifiable, Equatable {
    case message(EphemeralChatMessage)
    case tool(AgentToolTimeline.Entry)

    var id: UUID {
        switch self {
        case let .message(message): message.id
        case let .tool(entry): entry.id
        }
    }
}

/// What the island shows for a conversation.
///
/// The island used to drop every tool turn on the floor, so a question that made the agent
/// search the web or open a document showed the answer and no sign of how it was reached.
/// That was defensible while the island was a bare completion call with no tools; once #61
/// put it on the same agent loop it became the island claiming credit for work it would not
/// show — and the surface where trusting the answer matters most is the one floating over
/// someone else's window.
///
/// Rows rather than a filtered message list because the ordering is the point: a card has to
/// sit between the question that caused it and the answer that used it. Free of SwiftUI so
/// that ordering is testable without mounting a panel.
enum IslandThread {
    /// The rows for `messages`.
    ///
    /// - Parameter isStreaming: whether this conversation has a run in flight. Only the last
    ///   assistant message can be the one being written, so this marks that one and nothing
    ///   else — a spinner on an older bubble would claim a finished answer is still arriving.
    static func rows(for messages: [AgentMessage], isStreaming: Bool) -> [IslandRow] {
        let lastIndex = messages.count - 1
        return messages.enumerated().flatMap { index, message -> [IslandRow] in
            switch message.role {
            case .user:
                return [.message(chatMessage(message, isUser: true, isStreaming: false))]

            case .assistant:
                let live = isStreaming && index == lastIndex
                // An assistant turn that only asked for tools carries no prose. Rendering it
                // draws an empty bubble above the card that explains it, so it is dropped —
                // unless it is the one being written, which starts empty and fills in.
                guard live || !message.content.isEmpty else { return [] }
                return [.message(chatMessage(message, isUser: false, isStreaming: live))]

            case .toolCall:
                return AgentToolTimeline.entries(in: message, allMessages: messages)
                    // A call still waiting on the user is drawn by the pinned approval strip
                    // above the pill, where it cannot scroll out of reach. Emitting it here
                    // too put two cards for one call inside a 420pt panel, only one of them
                    // answerable, which reads as a rendering bug.
                    .filter { $0.status != .needsConfirmation }
                    .map(IslandRow.tool)

            case .toolResult:
                // Rendered inside the card for the call it answers, never as a row of its own.
                return []
            }
        }
    }

    private static func chatMessage(
        _ message: AgentMessage,
        isUser: Bool,
        isStreaming: Bool
    ) -> EphemeralChatMessage {
        EphemeralChatMessage(
            id: message.id,
            content: message.content,
            isUser: isUser,
            isStreaming: isStreaming,
            timestamp: message.timestamp
        )
    }
}
