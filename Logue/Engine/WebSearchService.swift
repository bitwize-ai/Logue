import Foundation
import os.log

// MARK: - Public Types

/// One row from a web search.
struct WebSearchResult {
    let title: String
    let url: URL
    let snippet: String
}

// MARK: - WebSearchService

/// Privacy-friendly web search via DuckDuckGo's HTML endpoint. Opt-in only —
/// gated by `AppConstants.UserDefaultsKeys.webSearchEnabled`. No API key.
///
/// Stays Apple-native: `URLSession` only, no third-party deps. HTML parsed
/// with regex (mirroring Sidekick's `DuckDuckGoSearch.swift`) — fragile to
/// upstream layout changes but no scraping framework needed.
actor WebSearchService {
    static let shared = WebSearchService()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "WebSearch")
    private let session: URLSession

    /// Per-host last-request timestamp. Throttles repeat hits at ~1/sec to be a
    /// good citizen of the public DuckDuckGo HTML endpoint. Capped to
    /// `maxThrottleEntries` with crude LRU-style eviction so a long-running
    /// session can't grow this dict without bound.
    private var hostLastRequest: [String: Date] = [:]
    private static let perHostMinIntervalSeconds: TimeInterval = 1.0
    private static let maxThrottleEntries = 100
    private static let throttleEvictTo = 80

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = [
            "User-Agent": AppConstants.WebSearch.userAgent,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        session = URLSession(configuration: config)
    }

    enum WebSearchError: Error, LocalizedError {
        case invalidQuery
        case requestFailed(String)
        case parseFailed
        case insecureURL

        var errorDescription: String? {
            switch self {
            case .invalidQuery: "Query is empty after sanitization."
            case let .requestFailed(reason): "Web request failed: \(reason)"
            case .parseFailed: "Could not parse search results."
            case .insecureURL: "Only HTTPS URLs are allowed."
            }
        }
    }

    // MARK: - Search

    /// Performs a search against `https://html.duckduckgo.com/html/?q=...` and
    /// returns up to `limit` results. Errors are thrown so callers can surface
    /// them as tool-result errors.
    func search(query: String, limit: Int = 5) async throws -> [WebSearchResult] {
        let safe = Self.sanitizeQuery(query)
        guard !safe.isEmpty else { throw WebSearchError.invalidQuery }

        guard let encoded = safe.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)")
        else {
            throw WebSearchError.invalidQuery
        }

        await throttle(host: url.host ?? "duckduckgo.com")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await sessionData(request: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebSearchError.requestFailed("HTTP \(code)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw WebSearchError.parseFailed
        }
        return Self.parseResults(html: html, limit: max(1, min(limit, AppConstants.WebSearch.maxResults)))
    }

    // MARK: - Page fetch

    /// Fetches `url` and returns plain text (HTML stripped). Capped at
    /// `AppConstants.WebSearch.maxFetchChars` to keep the agent's tool result
    /// under the truncation limit.
    func fetchPage(url: URL) async throws -> String {
        guard url.scheme?.lowercased() == "https" else {
            throw WebSearchError.insecureURL
        }
        await throttle(host: url.host ?? "")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await sessionData(request: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WebSearchError.requestFailed("HTTP \(code)")
        }

        // NSAttributedString HTML conversion handles entities, scripts, styles.
        let stripped: String
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) {
            stripped = attributed.string
        } else if let html = String(data: data, encoding: .utf8) {
            stripped = Self.stripHTML(html)
        } else {
            throw WebSearchError.parseFailed
        }

        let collapsed = stripped
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(AppConstants.WebSearch.maxFetchChars))
    }

    // MARK: - Throttle

    private func throttle(host: String) async {
        let now = Date.now
        if let last = hostLastRequest[host] {
            let elapsed = now.timeIntervalSince(last)
            let needed = Self.perHostMinIntervalSeconds - elapsed
            if needed > 0 {
                try? await Task.sleep(for: .milliseconds(Int(needed * 1000)))
            }
        }
        hostLastRequest[host] = Date.now
        // Evict oldest entries if the dict has grown past the cap. LRU-ish:
        // we keep the most-recently-used `throttleEvictTo` entries by date.
        // This runs O(n log n) on the eviction step but only when the cap is
        // exceeded — typical sessions hit only a handful of hosts.
        if hostLastRequest.count > Self.maxThrottleEntries {
            let kept = hostLastRequest
                .sorted { $0.value > $1.value }
                .prefix(Self.throttleEvictTo)
            hostLastRequest = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }

    // MARK: - URLSession bridge

    /// Wraps `URLSession.data(for:)` so we can throw a typed error instead of
    /// the framework's untyped one. Logs only `url.host` per CLAUDE.md.
    private func sessionData(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            logger.error(
                "URLSession failed for host \(request.url?.host ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw WebSearchError.requestFailed(error.localizedDescription)
        }
    }

    // MARK: - Static helpers

    /// Removes control chars + non-newline whitespace controls, caps length.
    nonisolated static func sanitizeQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed
            .filter { !$0.isNewline && $0.asciiValue != 0 }
        return String(filtered.prefix(AppConstants.WebSearch.maxQueryChars))
    }

    /// Parses DuckDuckGo's HTML SERP. Pattern matches Sidekick's regex but is
    /// scoped per-result so we extract title + URL + snippet together.
    nonisolated static func parseResults(html: String, limit: Int) -> [WebSearchResult] {
        // Each result is anchored by `<a class="result__a" href="...">title</a>`
        // followed by a `<a|div class="result__snippet">...</...>` block.
        let pattern = #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#
            + #"[\s\S]*?(?:class="result__snippet"[^>]*>([\s\S]*?)</(?:a|div)>)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsHtml = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))

        var results: [WebSearchResult] = []
        results.reserveCapacity(min(matches.count, limit))
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let rawHref = nsHtml.substring(with: match.range(at: 1))
            let titleHTML = nsHtml.substring(with: match.range(at: 2))
            let snippetHTML: String = if match.range(at: 3).location != NSNotFound {
                nsHtml.substring(with: match.range(at: 3))
            } else {
                ""
            }

            guard let resultURL = decodeDuckDuckGoHref(rawHref) else { continue }
            // CLAUDE.md: HTTPS only.
            guard resultURL.scheme?.lowercased() == "https" else { continue }

            let title = decodeHTML(stripHTML(titleHTML)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let snippet = decodeHTML(stripHTML(snippetHTML)).trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(WebSearchResult(title: title, url: resultURL, snippet: snippet))
            if results.count >= limit {
                break
            }
        }
        return results
    }

    /// DuckDuckGo wraps result URLs in `/l/?uddg=ENCODED&...`. Decode back to the real URL.
    nonisolated static func decodeDuckDuckGoHref(_ href: String) -> URL? {
        let normalized: String = if href.hasPrefix("//") {
            "https:" + href
        } else if href.hasPrefix("/") {
            "https://duckduckgo.com" + href
        } else {
            href
        }
        guard let components = URLComponents(string: normalized) else {
            return URL(string: href)
        }
        if let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = uddg.removingPercentEncoding,
           let real = URL(string: decoded)
        {
            return real
        }
        return components.url
    }

    /// Strips HTML tags. Lightweight regex; combined with `decodeHTML` it gives
    /// usable plaintext for snippets and titles.
    nonisolated static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Decodes a small set of common HTML entities. Avoids pulling in
    /// `NSAttributedString(html:)` for the hot path.
    nonisolated static func decodeHTML(_ html: String) -> String {
        var out = html
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&hellip;", "…"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
        ]
        for (entity, replacement) in entities {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}
