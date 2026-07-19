import Foundation

/// Phase C: Canvas state. The agent posts new versions through `push(...)`;
/// the chat view binds to `isOpen` to slide the right pane in/out.
@MainActor
@Observable
final class CanvasController {
    static let shared = CanvasController()

    private(set) var snapshots: [CanvasSnapshot] = []
    var activeID: UUID?

    var active: CanvasSnapshot? {
        guard let id = activeID else { return snapshots.last }
        return snapshots.first { $0.id == id }
    }

    private init() {}

    /// Append a new snapshot (auto-numbered) and surface it as active. If
    /// the language matches the previous snapshot's, treat it as an
    /// iteration of the same artifact; otherwise reset the version stack.
    func push(content: String, language: String) {
        if let previous = snapshots.last, previous.language.lowercased() != language.lowercased() {
            snapshots.removeAll()
        }
        let nextNumber = snapshots.count + 1
        let snapshot = CanvasSnapshot(
            label: "v\(nextNumber)",
            language: language,
            content: content
        )
        snapshots.append(snapshot)
        activeID = snapshot.id
    }

    func dismiss() {
        snapshots.removeAll()
        activeID = nil
    }

    /// Heuristic: should the agent's latest assistant message open the canvas?
    /// Triggers when the longest fenced code block exceeds 30 lines OR the
    /// language is preview-eligible (html / mermaid / svg).
    static func shouldOpenForResponse(_ markdown: String) -> (open: Bool, language: String, content: String)? {
        let pattern = #"```([a-zA-Z0-9_+\-]*)\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(markdown.startIndex ..< markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, range: range)
        guard !matches.isEmpty else { return nil }

        // Pick the longest block.
        var bestLang = ""
        var bestContent = ""
        var bestLines = 0
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let langRange = Range(match.range(at: 1), in: markdown),
                  let bodyRange = Range(match.range(at: 2), in: markdown)
            else { continue }
            let lang = String(markdown[langRange])
            let body = String(markdown[bodyRange])
            let lines = body.components(separatedBy: "\n").count
            if lines > bestLines {
                bestLang = lang
                bestContent = body
                bestLines = lines
            }
        }

        let previewable = ["html", "svg", "mermaid"].contains(bestLang.lowercased())
        if bestLines > 30 || previewable {
            return (true, bestLang.isEmpty ? "text" : bestLang, bestContent)
        }
        return nil
    }
}
