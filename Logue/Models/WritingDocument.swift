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
        case storedWidthMode = "widthMode"
        case icon, relationships, properties
    }

    /// Optional single-grapheme icon shown in lists and titles.
    /// Validate user input through `DocumentIcon.sanitised` before assigning.
    var icon: String?

    /// Typed metadata keyed by frontmatter name. Optional so documents saved before
    /// this field existed still decode — Swift's synthesized `Codable` throws
    /// `keyNotFound` for a missing non-optional key even when it has a default.
    var properties: [String: PropertyValue]?

    /// Non-nil properties, for reading.
    var propertyValues: [String: PropertyValue] {
        properties ?? [:]
    }

    /// Property keys in a stable sorted order, so the inspector does not reshuffle.
    var propertyKeys: [String] {
        propertyValues.keys.sorted()
    }

    func property(_ key: String) -> PropertyValue? {
        propertyValues[key]
    }

    /// Sets or removes a property. The key is sanitised, and a system-reserved or
    /// unusable key is ignored rather than stored.
    mutating func setProperty(_ key: String, value: PropertyValue?) {
        guard let sanitised = PropertyKey.sanitisedKey(key) else { return }

        var store = propertyValues
        if let value {
            store[sanitised] = value
        } else {
            store.removeValue(forKey: sanitised)
        }
        properties = store.isEmpty ? nil : store
    }

    /// Declared relationships, keyed by frontmatter name (`belongs_to`, `has`,
    /// `related_to`). Optional so documents saved before this field existed still
    /// decode — Swift's synthesized `Codable` throws `keyNotFound` for a missing
    /// non-optional key even when it has a default.
    ///
    /// Stored as raw strings rather than `[RelationshipKind: [String]]` so the JSON
    /// uses readable frontmatter keys and survives an unknown key from a newer build.
    var relationships: [String: [String]]?

    /// Declared relationships with unknown keys discarded.
    var typedRelationships: [RelationshipKind: [String]] {
        var result: [RelationshipKind: [String]] = [:]
        for (key, targets) in relationships ?? [:] {
            guard let kind = RelationshipKind(key: key), !targets.isEmpty else { continue }
            result[kind] = targets
        }
        return result
    }

    /// Replaces the targets for one relationship kind.
    ///
    /// Blank targets are discarded and duplicates collapsed case-insensitively, so
    /// the stored list matches what the graph can actually resolve. An empty result
    /// removes the key rather than persisting an empty array.
    mutating func setRelationship(_ kind: RelationshipKind, targets: [String]) {
        var seen = Set<String>()
        var cleaned: [String] = []
        for target in targets {
            let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            cleaned.append(trimmed)
        }

        var store = relationships ?? [:]
        if cleaned.isEmpty {
            store.removeValue(forKey: kind.key)
        } else {
            store[kind.key] = cleaned
        }
        relationships = store.isEmpty ? nil : store
    }

    /// Backing storage for `widthMode`. Optional so documents persisted before this
    /// property existed still decode — the synthesised decoder uses
    /// `decodeIfPresent` for optionals, where a non-optional would throw
    /// `keyNotFound` and make every existing document unreadable.
    var storedWidthMode: DocumentWidthMode?

    /// Editor content width for this document. Defaults to `.normal`.
    var widthMode: DocumentWidthMode {
        get { storedWidthMode ?? .normal }
        set { storedWidthMode = newValue }
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
