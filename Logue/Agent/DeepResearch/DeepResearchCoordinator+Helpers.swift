import Foundation
import os.log

// MARK: - DeepResearchCoordinator helpers

//
// Pure-static helpers extracted from `DeepResearchCoordinator` so the main
// type body stays under SwiftLint's `type_body_length` cap. Scope is JSON
// parsing, URL extraction, and Markdown insertion — none of these need actor
// isolation or instance state.

extension DeepResearchCoordinator {
    // MARK: - JSON parsing

    static func extractJSONArray(from response: String) -> String? {
        extractRawJSONArray(from: response)
    }

    /// Extracts the first balanced JSON array from a string. Handles markdown
    /// code fences and surrounding prose. Mirrors `MeetingPromptBuilder.extractJSONArray`.
    static func extractRawJSONArray(from response: String) -> String? {
        var cleaned = response
        if let fenceStart = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
            if let fenceEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
        }
        guard let arrayStart = cleaned.firstIndex(of: "[") else { return nil }
        var depth = 0
        var arrayEnd = arrayStart
        var inString = false
        var prev: Character = " "
        for index in cleaned[arrayStart...].indices {
            let ch = cleaned[index]
            if ch == "\"", prev != "\\" {
                inString.toggle()
            }
            if !inString {
                if ch == "[" {
                    depth += 1
                }
                if ch == "]" {
                    depth -= 1
                    if depth == 0 {
                        arrayEnd = index
                        break
                    }
                }
            }
            prev = ch
        }
        guard depth == 0 else { return nil }
        return String(cleaned[arrayStart ... arrayEnd])
    }

    struct RawSection: Decodable {
        let title: String
        let description: String
        let isSearchNeeded: Bool?
    }

    static func parseSections(json: String) -> [ResearchSection]? {
        guard let data = json.data(using: .utf8) else { return nil }
        let raw: [RawSection]
        do {
            raw = try JSONDecoder().decode([RawSection].self, from: data)
        } catch {
            // Surface the parse error + a snippet of what we tried to decode
            // so a developer can see why the LLM's plan didn't stick. CLAUDE.md
            // bans silent `try?` on JSON decodes precisely for this reason.
            Logger(subsystem: AppConstants.bundleID, category: "DeepResearch")
                .error(
                    "parseSections decode failed: \(error.localizedDescription, privacy: .public) | raw=\(json.prefix(200), privacy: .public)"
                )
            return nil
        }
        guard !raw.isEmpty else { return nil }
        return raw.map {
            ResearchSection(
                title: $0.title,
                description: $0.description,
                isSearchNeeded: $0.isSearchNeeded ?? true
            )
        }
    }

    struct RawDiagram: Decodable {
        let section: String
        let description: String
        let mermaid: String
    }

    static func parseDiagramOpportunities(json: String) -> [RawDiagram]? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode([RawDiagram].self, from: data)
        } catch {
            Logger(subsystem: AppConstants.bundleID, category: "DeepResearch")
                .error("parseDiagramOpportunities decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Source extraction

    /// Pulls out URLs from a string. Uses `NSDataDetector` so we catch both
    /// Markdown-link URLs and bare URLs.
    static func extractURLs(from text: String) -> [URL] {
        let detector: NSDataDetector
        do {
            detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            Logger(subsystem: AppConstants.bundleID, category: "DeepResearch")
                .error("NSDataDetector init failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let nsString = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap(\.url)
    }

    static func dedupeURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            // Use absoluteString for deduplication only (never log this key)
            let key = url.absoluteString
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    // MARK: - Markdown insertion

    /// Inserts `snippet` immediately after the line `## headingText` (case-insensitive
    /// match on the trimmed heading text). Returns nil if no match — caller leaves
    /// the draft unchanged.
    static func insertAfterHeading(
        in markdown: String,
        headingText: String,
        snippet: String
    ) -> String? {
        let target = headingText.lowercased().trimmingCharacters(in: .whitespaces)
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            // Match exactly `## title` — not `###` or deeper. Counting the
            // leading `#` run prevents H3/H4 with the same name from
            // accidentally claiming the diagram.
            let hashCount = trimmed.prefix { $0 == "#" }.count
            guard hashCount == 2 else { continue }
            let body = trimmed.dropFirst(hashCount).trimmingCharacters(in: .whitespaces)
            if body == target {
                var newLines = lines
                newLines.insert(snippet, at: idx + 1)
                newLines.insert("", at: idx + 1)
                return newLines.joined(separator: "\n")
            }
        }
        return nil
    }
}
