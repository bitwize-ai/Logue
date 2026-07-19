import Foundation

// MARK: - Inline Rewrite

extension PromptRegistry {
    enum InlineRewrite {
        /// v1.0.0 — System prompt for natural-language in-place rewriting of selected text.
        /// User content lives between `<content>` delimiters (CLAUDE.md security rule);
        /// instruction lives in the user message body.
        static let system = PromptTemplate(
            content: withBase("""
            You are editing a section of a user's document. Rewrite ONLY the content \
            between <content> tags following the user's instruction.

            RULES:
            - Preserve formatting (headings, lists, bold/italic, links) unless the \
            instruction explicitly asks to change it.
            - Match the original tone and voice unless told otherwise.
            - Do NOT add preamble like "Here is the rewrite" or "Rewritten:".
            - Do NOT wrap output in quotes or code fences.
            - Do NOT fabricate facts, names, numbers, or dates not present in the content.
            - Return the rewritten content ONLY — nothing else.
            - If the instruction is unclear or contradictory, return the original text unchanged.
            """),
            version: "1.0.0",
            key: "editor.inlineRewrite.system"
        )

        /// Builds the user prompt with the sanitized instruction + delimiter-wrapped content.
        /// Call sites must truncate `selectedText` to fit the context window before passing in.
        static func userPrompt(instruction: String, selectedText: String) -> String {
            """
            Instruction: \(instruction)

            <content>
            \(selectedText)
            </content>
            """
        }
    }
}
