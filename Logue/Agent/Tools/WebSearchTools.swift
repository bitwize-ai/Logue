import Foundation
import MLXLMCommon

// MARK: - WebSearchTool

/// Searches the public web via DuckDuckGo's HTML endpoint. Opt-in only — not
/// registered unless the user enables web search in Settings. `.sensitive`
/// clearance so each new conversation surfaces an Approve card before the
/// first network call (subsequent calls in the same conversation pass through
/// without re-prompting via the existing approval gate).
struct WebSearchTool: AgentTool {
    let name = "web_search"
    let description = """
    Search the public web for recent or general-knowledge information not in the user's \
    notes. Returns a list of results with title, URL, and snippet. Use this for current \
    events, factual lookups, or external references. Always cite the source URL in your \
    final answer.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "query": AgentToolSpec.stringParam("Search query (1-200 chars)"),
                "limit": AgentToolSpec.intParam("Maximum results (default 5, max 10)"),
            ],
            required: ["query"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawQuery = arguments["query"] as? String, !rawQuery.isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = min((arguments["limit"] as? Int) ?? 5, AppConstants.WebSearch.maxResults)

        let results: [WebSearchResult]
        do {
            results = try await WebSearchService.shared.search(query: rawQuery, limit: limit)
        } catch {
            throw AgentToolError.executionFailed(error.localizedDescription)
        }
        guard !results.isEmpty else {
            return "No web results found for \"\(rawQuery)\"."
        }

        var output = "Found \(results.count) web result(s) for \"\(rawQuery)\":\n"
        for (idx, result) in results.enumerated() {
            output += "\n\(idx + 1). \(result.title)"
            output += "\n   URL: \(result.url.absoluteString)"
            if !result.snippet.isEmpty {
                output += "\n   Snippet: \(String(result.snippet.prefix(280)))"
            }
        }
        return output
    }
}

// MARK: - FetchWebPageTool

/// Fetches a specific URL and returns plaintext (HTML stripped). Opt-in only.
/// `.sensitive` because the page content is unverified — surface to user.
struct FetchWebPageTool: AgentTool {
    let name = "fetch_web_page"
    let description = """
    Fetch a specific HTTPS URL and return its visible text content (HTML stripped, capped \
    at 16KB). Use after `web_search` to read a result in detail. Only HTTPS is supported.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "url": AgentToolSpec.stringParam("Fully-qualified HTTPS URL"),
            ],
            required: ["url"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let urlString = arguments["url"] as? String, !urlString.isEmpty else {
            throw AgentToolError.missingParameter("url")
        }
        guard let url = URL(string: urlString) else {
            throw AgentToolError.invalidParameter("url", "Not a valid URL")
        }
        guard url.scheme?.lowercased() == "https" else {
            throw AgentToolError.invalidParameter("url", "Only HTTPS URLs are allowed")
        }

        do {
            let content = try await WebSearchService.shared.fetchPage(url: url)
            guard !content.isEmpty else {
                return "Page at \(url.host ?? "?") returned no readable text."
            }
            // The host is logged; the full URL is included only in the tool result
            // (which the LLM uses to cite). It is not written to the system log.
            return "Content from \(url.absoluteString) (\(content.count) chars):\n\n\(content)"
        } catch {
            throw AgentToolError.executionFailed(error.localizedDescription)
        }
    }
}
