import Foundation

// MARK: - RewriteResult

struct RewriteResult: Codable, Sendable {
    let style: String
    let originalText: String
    let rewrittenText: String
}

/// A document managed in Logue's library.
struct WritingDocument: Identifiable, Codable, Sendable {
    var id: UUID = .init()
    var title: String = "Untitled Document"
    /// Plain text body of the document.
    var body: String = ""
    var goalMode: WritingGoalMode = .casual
    var createdAt: Date = .init()
    var modifiedAt: Date = .init()
    var isPinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, body, goalMode, createdAt, modifiedAt
        case isPinned = "isFavorited"
        case score, spaceID, tags, chatMessages, isTrashed, trashedAt
        case reviewGrade, reviewReactions, factChecks, piiFindings
        case vocabSuggestions, aiDetectionResult, plagiarismResult, rewriteResult
    }

    /// The last computed writing score; nil until first analysis.
    var score: WritingScore?
    /// Space this document belongs to; nil = unfiled.
    var spaceID: UUID?
    /// User-assigned tags for organisation.
    var tags: [String] = []
    /// AI chat conversation history for this document.
    var chatMessages: [ChatMessage] = []
    /// Whether this document is in the trash.
    var isTrashed: Bool = false
    /// When the document was moved to trash.
    var trashedAt: Date?

    // MARK: - Cached AI Panel Results

    /// Review panel: overall grade with per-category scores.
    var reviewGrade: OverallGrade?
    /// Review panel: reader emotion reactions per section.
    var reviewReactions: [SectionReaction]?
    /// Verify panel: fact-check results.
    var factChecks: [FactCheck]?
    /// Verify panel: PII/privacy findings.
    var piiFindings: [PIIFinding]?
    /// Vocabulary enhancement suggestions.
    var vocabSuggestions: [VocabSuggestion]?
    /// AI content detector result text.
    var aiDetectionResult: String?
    /// Plagiarism checker result text.
    var plagiarismResult: String?
    /// Rewrite panel cached result.
    var rewriteResult: RewriteResult?

    // MARK: - Derived

    var wordCount: Int {
        body.split { $0.isWhitespace || $0.isNewline }.count
    }

    var readingTimeMinutes: Double {
        Double(wordCount) / 238.0 // average adult reading speed
    }

    var readingTimeLabel: String {
        let minutes = readingTimeMinutes
        if minutes < 1 {
            return "< 1 min read"
        }
        return "\(Int(ceil(minutes))) min read"
    }

    /// First 120 characters of body as a preview snippet, excluding markdown table syntax.
    var snippet: String {
        let lines = body.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip markdown table rows (| ... |) and separator lines (| --- |)
            guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return true }
            return false
        }
        let joined = filtered.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > 120 else { return joined }
        return String(joined.prefix(120)) + "…"
    }
}
