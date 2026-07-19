import Foundation

// MARK: - Memory Prompts

extension PromptRegistry {
    enum Memory {
        /// v1.0.0 — System prompt for extracting one persistent personal fact from a
        /// user message. Mirrors Sidekick's `Memories.swift` extraction grammar:
        /// the response must start with "The user" or be the literal word "nil"
        /// when nothing personal/persistent is in the message.
        static let extractionSystem = PromptTemplate(
            content: """
            You extract persistent personal information about the user from their messages \
            so a future conversation can be more helpful.

            Rules:
            - Only extract information that will still be true days or weeks from now \
              (preferences, role, interests, habits, ongoing projects).
            - Never extract task-specific or one-off context (e.g. "the user wants to summarize this meeting").
            - Never extract information about other people, companies, or third parties.
            - Never invent or paraphrase beyond what the message actually says.
            - Respond in the format: `The user [verb] [information].`
            - If nothing persistent is in the message, respond with the single word: nil
            - Output ONLY that one line. No preamble, no explanation, no markdown.
            """,
            version: "1.0.0",
            key: "memory.extraction.system"
        )

        /// Builds the user-facing prompt for extraction. The user's message is wrapped
        /// in `<message>...</message>` per CLAUDE.md security policy.
        static func extractionPrompt(message: String) -> String {
            """
            <message>
            \(message)
            </message>
            """
        }

        // MARK: - Recall Injection

        /// Renders the recall block injected into the agent system prompt. Empty array
        /// returns an empty string so the system prompt stays unchanged when no
        /// memories have accumulated.
        static func recallBlock(memories: [String]) -> String {
            guard !memories.isEmpty else { return "" }
            var block = "\n\n<user_memories>\n"
            for memory in memories {
                block += "- \(memory)\n"
            }
            block += """
            </user_memories>

            Use these memories to personalize responses when relevant. \
            Don't reference them out loud unless the user asks what you remember.
            """
            return block
        }
    }
}
