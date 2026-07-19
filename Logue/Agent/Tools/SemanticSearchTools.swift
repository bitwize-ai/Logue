import Foundation
import MLXLMCommon

// MARK: - SemanticSearchMeetingsTool

/// Embedding-based semantic search across meeting transcripts. Complements the
/// FTS5 keyword search exposed by `SearchMeetingsTool` — use this when the user
/// asks about a concept rather than a literal word ("when did we discuss
/// backpressure?" vs `search_meetings` for an exact term).
struct SemanticSearchMeetingsTool: AgentTool {
    let name = "semantic_search_meetings"
    let description = """
    Semantic (meaning-based) search across meeting transcripts. Use when the user \
    asks about a topic or concept that may not match exact keywords. Returns the \
    top matching transcript snippets with meeting title, date, and similarity score.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "query": AgentToolSpec.stringParam("Natural-language description of what to search for"),
                "limit": AgentToolSpec.intParam("Maximum results (default 5, max 10)"),
            ],
            required: ["query"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = min((arguments["limit"] as? Int) ?? 5, 10)

        // Phase E: use graph-enhanced retrieval when graph data exists (gated by EntityExtractor.isEnabled).
        let hits: [VectorHit] = if await EntityExtractor.shared.isEnabled {
            await GraphRetriever.shared.search(query: query, namespaces: ["meeting"], topK: limit)
        } else {
            await SemanticIndex.shared.searchMeetings(query: query, limit: limit)
        }
        guard !hits.isEmpty else {
            return "No meetings semantically matched \"\(query)\". Try `search_meetings` for exact-keyword matches."
        }

        var output = "Found \(hits.count) semantically-related meeting snippet(s) for \"\(query)\":\n"
        for (idx, hit) in hits.enumerated() {
            let title = hit.metadata?["title"] ?? "Untitled meeting"
            let date = hit.metadata?["date"].flatMap { Self.formatISODate($0) } ?? "unknown date"
            output += "\n\(idx + 1). [Meeting \"\(title)\", \(date)]"
            output += "\n   ID: \(hit.itemID)"
            output += "\n   Score: \(String(format: "%.2f", hit.score))"
            output += "\n   Snippet: \(String(hit.chunkText.prefix(280)))"
        }
        return output
    }

    private static func formatISODate(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - SemanticSearchDocumentsTool

/// Embedding-based semantic search across document bodies. Complements
/// `search_documents` (keyword) for concept-level queries.
struct SemanticSearchDocumentsTool: AgentTool {
    let name = "semantic_search_documents"
    let description = """
    Semantic (meaning-based) search across document bodies. Use when the user \
    asks about a topic or concept rather than an exact phrase. Returns top \
    matching snippets with document title and similarity score.
    """
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "query": AgentToolSpec.stringParam("Natural-language description of what to search for"),
                "limit": AgentToolSpec.intParam("Maximum results (default 5, max 10)"),
            ],
            required: ["query"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = min((arguments["limit"] as? Int) ?? 5, 10)

        // Phase E: use graph-enhanced retrieval when graph data exists.
        let hits: [VectorHit] = if await EntityExtractor.shared.isEnabled {
            await GraphRetriever.shared.search(query: query, namespaces: ["document"], topK: limit)
        } else {
            await SemanticIndex.shared.searchDocuments(query: query, limit: limit)
        }
        guard !hits.isEmpty else {
            return "No documents semantically matched \"\(query)\". Try `search_documents` for exact-keyword matches."
        }

        var output = "Found \(hits.count) semantically-related document snippet(s) for \"\(query)\":\n"
        for (idx, hit) in hits.enumerated() {
            let title = hit.metadata?["title"] ?? "Untitled document"
            output += "\n\(idx + 1). [Document \"\(title)\"]"
            output += "\n   ID: \(hit.itemID)"
            output += "\n   Score: \(String(format: "%.2f", hit.score))"
            output += "\n   Snippet: \(String(hit.chunkText.prefix(280)))"
        }
        return output
    }
}
