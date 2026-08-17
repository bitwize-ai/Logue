import Foundation

/// What the sources panel would show for a conversation.
///
/// Extracted so the panel and the control that reveals it answer the *same* question.
/// They used to answer two: the panel scanned every tool result for URLs, while the
/// toolbar button asked whether any tool was named like a web or library tool. A
/// conversation that cited a URL from `read_file_at_path` or `run_javascript` therefore
/// had sources the panel would happily render and no way to open it.
enum SourcesPanelContent {
    /// Tool names whose arguments name a meeting or document worth listing under
    /// "Referenced". Matched on the name because the argument shape varies per tool.
    static func isReferenceTool(_ toolName: String) -> Bool {
        toolName.contains("meeting") || toolName.contains("document")
    }

    static func citedURLs(in messages: [AgentMessage], limit: Int = 10) -> [URL] {
        let pattern = #"https?://[^\s\)\]\"'<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        var urls: [URL] = []
        var seen = Set<String>()
        for msg in messages {
            guard let text = msg.toolResult?.output else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let hit = match, let hitRange = Range(hit.range, in: text) else { return }
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
        return Array(urls.prefix(limit))
    }

    /// Keys identifying each referenced meeting or document, in first-seen order.
    static func referenceKeys(in messages: [AgentMessage], limit: Int = 8) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()
        for msg in messages {
            for call in msg.toolCalls where isReferenceTool(call.toolName) {
                let key = "\(call.toolName):\(call.arguments)"
                guard !call.arguments.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                keys.append(key)
            }
        }
        return Array(keys.prefix(limit))
    }

    /// Whether the panel has anything at all to render. The single source of truth for
    /// both the panel's own empty state and whether its toolbar button appears.
    static func hasContent(messages: [AgentMessage], attachmentCount: Int) -> Bool {
        if attachmentCount > 0 {
            return true
        }
        return hasAnswerSources(in: messages)
    }

    /// Whether the *agent* has produced anything worth showing — references or cited URLs.
    ///
    /// Separate from `hasContent` because the panel and its auto-open ask different questions.
    /// "Is there anything to draw?" counts a file the user has staged in the prompt bar; "has the
    /// agent sourced an answer?" must not. Folding the two together meant dropping a PDF onto
    /// Home's landing threw open a 280pt panel over the screen whose own comment calls a panel
    /// there "a dead half of the window" — and sending the message closed it again, because
    /// clearing the attachments took the condition back down.
    static func hasAnswerSources(in messages: [AgentMessage]) -> Bool {
        if !referenceKeys(in: messages).isEmpty {
            return true
        }
        return !citedURLs(in: messages).isEmpty
    }
}
