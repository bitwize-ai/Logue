import Foundation

// MARK: - Content

/// The half of a document a person writes and edits.
///
/// Split out so it can be stored as a plain `.md` file with YAML frontmatter while
/// AI-derived state stays encrypted. Everything here has a natural representation in
/// markdown — prose in the body, metadata in frontmatter, space placement as a
/// directory.
struct DocumentContent: Codable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var goalMode: WritingGoalMode
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var spaceID: UUID?
    var isTrashed: Bool
    var trashedAt: Date?
    var icon: String?
    var properties: [String: PropertyValue]?
    var relationships: [String: [String]]?
    var storedWidthMode: DocumentWidthMode?
    var storedIsOrganised: Bool?
}

// MARK: - Derived

/// The half the app computes: AI analysis, chat history, cached panel results.
///
/// Kept out of the markdown file for two reasons. It has no sensible frontmatter
/// representation and would be lossy through YAML; and it is never hand-edited, so
/// separating it cannot create a conflict.
struct DocumentDerived: Codable, Sendable {
    var id: UUID
    var score: WritingScore?
    var chatMessages: [ChatMessage]
    var reviewGrade: OverallGrade?
    var reviewReactions: [SectionReaction]?
    var factChecks: [FactCheck]?
    var piiFindings: [PIIFinding]?
    var vocabSuggestions: [VocabSuggestion]?
    var aiDetectionResult: String?
    var plagiarismResult: String?
    var rewriteResult: RewriteResult?

    /// Whether there is anything worth persisting.
    var isEmpty: Bool {
        score == nil
            && chatMessages.isEmpty
            && reviewGrade == nil
            && reviewReactions == nil
            && factChecks == nil
            && piiFindings == nil
            && vocabSuggestions == nil
            && aiDetectionResult == nil
            && plagiarismResult == nil
            && rewriteResult == nil
    }
}

// MARK: - Splitting and recomposing

extension WritingDocument {
    var content: DocumentContent {
        DocumentContent(
            id: id,
            title: title,
            body: body,
            tags: tags,
            goalMode: goalMode,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isPinned: isPinned,
            spaceID: spaceID,
            isTrashed: isTrashed,
            trashedAt: trashedAt,
            icon: icon,
            properties: properties,
            relationships: relationships,
            storedWidthMode: storedWidthMode,
            storedIsOrganised: storedIsOrganised
        )
    }

    var derived: DocumentDerived {
        DocumentDerived(
            id: id,
            score: score,
            chatMessages: chatMessages,
            reviewGrade: reviewGrade,
            reviewReactions: reviewReactions,
            factChecks: factChecks,
            piiFindings: piiFindings,
            vocabSuggestions: vocabSuggestions,
            aiDetectionResult: aiDetectionResult,
            plagiarismResult: plagiarismResult,
            rewriteResult: rewriteResult
        )
    }

    /// Rebuilds a document from its two halves.
    ///
    /// The content half owns identity: it is the durable, user-visible record, so if a
    /// stray derived file carries a different id the content wins rather than the
    /// document silently changing identity.
    init(content: DocumentContent, derived: DocumentDerived?) {
        self.init()

        id = content.id
        title = content.title
        body = content.body
        tags = content.tags
        goalMode = content.goalMode
        createdAt = content.createdAt
        modifiedAt = content.modifiedAt
        isPinned = content.isPinned
        spaceID = content.spaceID
        isTrashed = content.isTrashed
        trashedAt = content.trashedAt
        icon = content.icon
        properties = content.properties
        relationships = content.relationships
        storedWidthMode = content.storedWidthMode
        storedIsOrganised = content.storedIsOrganised

        guard let derived else { return }
        score = derived.score
        chatMessages = derived.chatMessages
        reviewGrade = derived.reviewGrade
        reviewReactions = derived.reviewReactions
        factChecks = derived.factChecks
        piiFindings = derived.piiFindings
        vocabSuggestions = derived.vocabSuggestions
        aiDetectionResult = derived.aiDetectionResult
        plagiarismResult = derived.plagiarismResult
        rewriteResult = derived.rewriteResult
    }
}
