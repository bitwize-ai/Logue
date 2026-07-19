import Foundation

// MARK: - ModelAction

/// Every logical AI action in the app. Used as the key for the centralized
/// action-to-model mapping in `ModelManager`.
///
/// Today every action resolves to the single active model, but this enum
/// lets us assign different models per action in the future by editing
/// the central map in one place.
enum ModelAction: String, CaseIterable, Codable, Identifiable {
    // Document analysis
    case grammarCheck
    case clarityCheck
    case toneDetect

    // Editor panels
    case chat
    case rephrase
    case generate
    case rewrite
    case vocabularyEnhancement

    // Verification panels
    case factCheck
    case plagiarismCheck
    case aiGrader
    case piiDetection
    case aiContentDetect
    case citationFinder
    case readerReactions

    /// Meeting
    case meetingSummary

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .grammarCheck: "Grammar Check"
        case .clarityCheck: "Clarity Check"
        case .toneDetect: "Tone Detection"
        case .chat: "AI Chat"
        case .rephrase: "Rephrase"
        case .generate: "Generate"
        case .rewrite: "Rewrite"
        case .vocabularyEnhancement: "Vocabulary"
        case .factCheck: "Fact Check"
        case .plagiarismCheck: "Plagiarism Check"
        case .aiGrader: "Writing Score"
        case .piiDetection: "Privacy Scan"
        case .aiContentDetect: "AI Content Detector"
        case .citationFinder: "Citation Finder"
        case .readerReactions: "Reader Reactions"
        case .meetingSummary: "Meeting Summary"
        }
    }
}
