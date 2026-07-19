import Foundation
import MLXLMCommon
import os.log

// MARK: - RenderDiagramTool

/// Renders a Mermaid diagram to an SVG file the agent can reference inline via
/// Markdown image syntax. On parse failure, the tool's error result includes the
/// underlying parser message + a Mermaid syntax cheatsheet so the model can
/// self-correct on its next turn (Phase 1.2 self-correcting feedback handles the
/// retry framing).
struct RenderDiagramTool: AgentTool {
    let name = "render_diagram"
    let description = """
    Renders a Mermaid diagram from the supplied Mermaid markup and saves it as an SVG. \
    Returns a Markdown image reference to embed in your response. Supports flowcharts, \
    sequence diagrams, class diagrams, state diagrams, ER diagrams, and gantt charts. \
    Wrap node text containing spaces or punctuation in double quotes.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "mermaid_code": AgentToolSpec.stringParam(
                    "Mermaid markup (e.g. \"flowchart TD\\n A --> B\"). Wrap node text with spaces in double quotes."
                ),
                "diagram_name": AgentToolSpec.stringParam(
                    "Short filename-friendly title for the diagram (optional, defaults to a timestamp)"
                ),
            ],
            required: ["mermaid_code"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawCode = arguments["mermaid_code"] as? String, !rawCode.isEmpty else {
            throw AgentToolError.missingParameter("mermaid_code")
        }
        let cleanedCode = Self.stripMarkdownFences(rawCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCode.isEmpty else {
            throw AgentToolError.invalidParameter("mermaid_code", "Empty after stripping fences")
        }

        let rawName = (arguments["diagram_name"] as? String) ?? ""
        let name = Self.sanitizeFilename(rawName)

        let svg: String
        do {
            svg = try await MermaidRenderer.shared.renderSVG(code: cleanedCode)
        } catch let MermaidRenderer.MermaidError.parseFailed(detail) {
            // Hand the LLM the parser error + a syntax cheatsheet. The graph's
            // self-correcting feedback (Phase 1.2) will format this for retry.
            let cheatsheet = await MainActor.run { MermaidRenderer.shared.cheatsheetText }
            let cheatsheetBlock = cheatsheet.isEmpty ? "" : """


            Mermaid syntax reference (use this to fix the diagram):

            \(cheatsheet)
            """
            let baseMsg = "Mermaid parse error: \(detail). "
                + "Common fix: wrap node text containing spaces or punctuation in double quotes "
                + "(e.g. `A[\"my text\"]` instead of `A[my text]`)."
            throw AgentToolError.executionFailed(baseMsg + cheatsheetBlock)
        } catch {
            throw AgentToolError.executionFailed(error.localizedDescription)
        }

        let outputURL = Self.outputURL(name: name)
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try svg.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw AgentToolError.executionFailed("Failed to save SVG: \(error.localizedDescription)")
        }

        // Return Markdown image syntax so the assistant can drop it directly into
        // its reply. The path is the file URL the chat view can resolve.
        let escapedPath = outputURL.path(percentEncoded: true)
        return """
        Saved diagram to \(outputURL.path(percentEncoded: false)).

        Embed it in your response with:

        ![Diagram](\(escapedPath))
        """
    }

    // MARK: - Helpers

    /// Strips ```mermaid / ``` fences if the model wrapped its output in them.
    private static func stripMarkdownFences(_ raw: String) -> String {
        var stripped = raw
        stripped = stripped.replacingOccurrences(of: "```mermaid", with: "")
        stripped = stripped.replacingOccurrences(of: "```", with: "")
        return stripped
    }

    /// Sanitizes a user-supplied diagram name for use as a filename. Keeps
    /// alphanumerics, underscore, hyphen; collapses everything else to `-`.
    private static func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return "diagram-\(formatter.string(from: .now))"
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let filtered = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        // `String(prefix(60))` not `prefix(60).description` — the latter calls
        // CustomStringConvertible on Substring, which on some types yields a
        // quoted form (`"foo"`) and would break the saved filename.
        return String(String(filtered).prefix(60))
    }

    /// Output location for rendered diagrams. Per-app-cache so they don't bloat
    /// the user's iCloud-backed Application Support tree.
    private static func outputURL(name: String) -> URL {
        let dir = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory)
            .appending(path: AppConstants.bundleID, directoryHint: .isDirectory)
            .appending(path: "AgentDiagrams", directoryHint: .isDirectory)
        return dir.appending(path: "\(name).svg")
    }
}
