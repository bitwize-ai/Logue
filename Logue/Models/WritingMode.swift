import Foundation

// MARK: - Writing Mode

/// Represents the type of writing operation for cross-app and in-app writing features.
enum WritingMode: String, CaseIterable, Identifiable {
    // Core
    case improve
    case rewrite
    case moreFormal = "more_formal"
    case shorter
    case expand
    case grammar

    // Content
    case article
    case brainstorm
    case conclusion
    case formalLetter = "formal_letter"

    // Text Editing
    case fullParagraph = "full_paragraph"
    case outline
    case paragraphRewriter = "paragraph_rewriter"
    case rewording
    case sentenceRewriter = "sentence_rewriter"
    case summarizing
    case title
    case sentences

    // Job Search
    case coverLetter = "cover_letter"
    case linkedinHeadline = "linkedin_headline"
    case resumeObjective = "resume_objective"
    case resumeSkills = "resume_skills"

    // Work
    case businessPlan = "business_plan"
    case businessReport = "business_report"
    case email
    case executiveSummary = "executive_summary"
    case jobDescription = "job_description"
    case resignationLetter = "resignation_letter"
    case valueProposition = "value_proposition"

    // Marketing
    case blogPost = "blog_post"
    case blogPostTitle = "blog_post_title"
    case businessName = "business_name"
    case headline
    case instagramCaption = "instagram_caption"
    case linkedinPost = "linkedin_post"
    case metaDescription = "meta_description"
    case metaTitle = "meta_title"
    case productDescription = "product_description"
    case slogan

    // Students
    case abstract
    case essayTitle = "essay_title"
    case personalStatement = "personal_statement"
    case poem
    case thesisStatement = "thesis_statement"
    case topicSentences = "topic_sentences"

    var id: String {
        rawValue
    }

    /// Core quick-action modes shown as chips in the floating panel.
    static var quickActions: [WritingMode] {
        [.improve, .rewrite, .moreFormal, .shorter, .expand, .grammar]
    }

    /// Featured modes shown as cards in the floating panel.
    static var featured: [WritingMode] {
        [.article, .brainstorm, .conclusion, .formalLetter]
    }

    var displayName: String {
        switch self {
        case .improve: "Improve"
        case .rewrite: "Rewrite"
        case .moreFormal: "More Formal"
        case .shorter: "Shorter"
        case .expand: "Expand"
        case .grammar: "Grammar"
        case .article: "Article Draft"
        case .brainstorm: "Brainstorm"
        case .conclusion: "Conclusion"
        case .formalLetter: "Formal Letter"
        case .fullParagraph: "Full Paragraph"
        case .outline: "Outline"
        case .paragraphRewriter: "Paragraph Rewriter"
        case .rewording: "Rewording"
        case .sentenceRewriter: "Sentence Rewriter"
        case .summarizing: "Summarize"
        case .title: "Title Maker"
        case .sentences: "Sentences"
        case .coverLetter: "Cover Letter"
        case .linkedinHeadline: "LinkedIn Headline"
        case .resumeObjective: "Resume Objective"
        case .resumeSkills: "Resume Skills"
        case .businessPlan: "Business Plan"
        case .businessReport: "Business Report"
        case .email: "Email"
        case .executiveSummary: "Executive Summary"
        case .jobDescription: "Job Description"
        case .resignationLetter: "Resignation Letter"
        case .valueProposition: "Value Proposition"
        case .blogPost: "Blog Post"
        case .blogPostTitle: "Blog Title"
        case .businessName: "Business Name"
        case .headline: "Headline"
        case .instagramCaption: "Instagram Caption"
        case .linkedinPost: "LinkedIn Post"
        case .metaDescription: "Meta Description"
        case .metaTitle: "Meta Title"
        case .productDescription: "Product Description"
        case .slogan: "Slogan"
        case .abstract: "Abstract"
        case .essayTitle: "Essay Title"
        case .personalStatement: "Personal Statement"
        case .poem: "Poem"
        case .thesisStatement: "Thesis Statement"
        case .topicSentences: "Topic Sentences"
        }
    }

    var description: String {
        switch self {
        case .improve: "Enhance clarity and readability"
        case .rewrite: "Complete rewrite with fresh perspective"
        case .moreFormal: "Adjust tone to be more professional"
        case .shorter: "Condense while keeping key points"
        case .expand: "Add detail and depth"
        case .grammar: "Fix grammar and punctuation"
        case .article: "Generate a structured article draft"
        case .brainstorm: "Generate ideas and suggestions"
        case .conclusion: "Create an impactful closing"
        case .formalLetter: "Draft a professional letter"
        case .fullParagraph: "Write entire paragraphs from scratch"
        case .outline: "Structure your ideas into an outline"
        case .paragraphRewriter: "Rephrase entire paragraphs"
        case .rewording: "Reword text quickly"
        case .sentenceRewriter: "Rephrase individual sentences"
        case .summarizing: "Turn complex ideas into concise summaries"
        case .title: "Craft compelling titles"
        case .sentences: "Create well-structured sentences"
        case .coverLetter: "Personalized cover letters"
        case .linkedinHeadline: "Standout LinkedIn headlines"
        case .resumeObjective: "Compelling resume objective"
        case .resumeSkills: "Compelling list of skills"
        case .businessPlan: "Goal-oriented business plan"
        case .businessReport: "Formatted business report"
        case .email: "Clear and personable emails"
        case .executiveSummary: "Draft an executive summary"
        case .jobDescription: "Standout job descriptions"
        case .resignationLetter: "Navigate transitions smoothly"
        case .valueProposition: "Compelling value proposition"
        case .blogPost: "Polished blog post"
        case .blogPostTitle: "Perfect blog title"
        case .businessName: "Unique, brand-ready names"
        case .headline: "Attention-grabbing headlines"
        case .instagramCaption: "Engaging caption instantly"
        case .linkedinPost: "Professional LinkedIn posts"
        case .metaDescription: "SEO-friendly meta descriptions"
        case .metaTitle: "Click-worthy meta titles"
        case .productDescription: "High-converting descriptions"
        case .slogan: "Catchy slogan for your brand"
        case .abstract: "Summarize key points"
        case .essayTitle: "Thought-provoking essay titles"
        case .personalStatement: "Compelling application essays"
        case .poem: "Beautiful, AI-crafted poems"
        case .thesisStatement: "Strong thesis statements"
        case .topicSentences: "Focused topic sentences"
        }
    }

    var iconName: String {
        switch self {
        case .improve: "sparkles"
        case .rewrite: "arrow.triangle.2.circlepath"
        case .moreFormal: "person.fill"
        case .shorter: "scissors"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .grammar: "textformat.abc"
        case .article: "doc.text"
        case .brainstorm: "lightbulb.fill"
        case .conclusion: "flag.checkered"
        case .formalLetter: "envelope.fill"
        case .fullParagraph: "paragraphsign"
        case .outline: "list.bullet.rectangle"
        case .paragraphRewriter: "arrow.2.squarepath"
        case .rewording: "text.cursor"
        case .sentenceRewriter: "character.cursor.ibeam"
        case .summarizing: "arrow.down.right.and.arrow.up.left"
        case .title: "textformat.size"
        case .sentences: "lineweight"
        case .coverLetter: "doc.richtext"
        case .linkedinHeadline: "person.text.rectangle"
        case .resumeObjective: "target"
        case .resumeSkills: "star.circle"
        case .businessPlan: "chart.bar.doc.horizontal"
        case .businessReport: "doc.plaintext"
        case .email: "envelope.badge"
        case .executiveSummary: "doc.on.clipboard"
        case .jobDescription: "person.badge.plus"
        case .resignationLetter: "arrow.right.square"
        case .valueProposition: "gift"
        case .blogPost: "newspaper"
        case .blogPostTitle: "text.format.superscript"
        case .businessName: "building.2"
        case .headline: "megaphone"
        case .instagramCaption: "camera.macro"
        case .linkedinPost: "network"
        case .metaDescription: "link"
        case .metaTitle: "text.magnifyingglass"
        case .productDescription: "cart"
        case .slogan: "quote.bubble"
        case .abstract: "doc.text.magnifyingglass"
        case .essayTitle: "graduationcap"
        case .personalStatement: "person.crop.circle.badge.checkmark"
        case .poem: "heart.text.square"
        case .thesisStatement: "bolt.horizontal"
        case .topicSentences: "text.alignleft"
        }
    }

    /// Builds the full LLM prompt for this writing mode.
    /// Sourced from `PromptRegistry.Writing`.
    func buildPrompt(for text: String, params: [String: String] = [:]) -> String {
        PromptRegistry.Writing.prompt(for: self, text: text, params: params)
    }
}

// MARK: - Letter Mode

enum LetterMode: String, CaseIterable, Identifiable {
    case businessFormal = "business_formal"
    case friendlyFormal = "friendly_formal"
    case complaint
    case application
    case thankYou = "thank_you"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .businessFormal: "Business Formal"
        case .friendlyFormal: "Friendly Formal"
        case .complaint: "Complaint"
        case .application: "Application"
        case .thankYou: "Thank You"
        }
    }
}

// MARK: - Writing Context

/// Context passed to a writing feature for processing.
struct WritingContext {
    var originalText: String
    var selectedText: String
    var mode: WritingMode
    var additionalParams: [String: String]

    init(
        originalText: String,
        selectedText: String = "",
        mode: WritingMode = .improve,
        additionalParams: [String: String] = [:]
    ) {
        self.originalText = originalText
        self.selectedText = selectedText.isEmpty ? originalText : selectedText
        self.mode = mode
        self.additionalParams = additionalParams
    }
}

// MARK: - Writing Result

/// Result returned by a writing feature.
struct WritingResult {
    var improvedText: String
    var alternatives: [String]
    var confidence: Double
    var featureId: String
    var metadata: [String: String]

    init(
        improvedText: String,
        alternatives: [String] = [],
        confidence: Double = 0.8,
        featureId: String = "",
        metadata: [String: String] = [:]
    ) {
        self.improvedText = improvedText
        self.alternatives = alternatives
        self.confidence = confidence
        self.featureId = featureId
        self.metadata = metadata
    }
}

// MARK: - Writing Feature Error

enum WritingFeatureError: Error, LocalizedError {
    case emptyInput
    case unsupportedMode(WritingMode)
    case modelNotLoaded
    case responseParseError(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "No text provided for processing."
        case let .unsupportedMode(mode):
            "Mode '\(mode.displayName)' is not supported."
        case .modelNotLoaded:
            "No AI model is loaded. Please download and activate a model in Settings."
        case let .responseParseError(detail):
            "Failed to parse AI response: \(detail)"
        case .timeout:
            "Request timed out."
        case .cancelled:
            "Request was cancelled."
        }
    }
}

// MARK: - Processing State

enum WritingProcessingState {
    case idle
    case processing(feature: String)
    case streaming(partial: String)
    case completed(WritingResult)
    case failed(String)

    var isProcessing: Bool {
        switch self {
        case .processing, .streaming: true
        default: false
        }
    }
}
