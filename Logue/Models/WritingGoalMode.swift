import Foundation

/// Writing goal that shapes the LLM's grammar and style analysis.
enum WritingGoalMode: String, CaseIterable, Codable, Sendable {
    case academic
    case business
    case casual
    case creative
    case technical

    var displayName: String {
        switch self {
        case .academic: "Academic"
        case .business: "Business"
        case .casual: "Casual"
        case .creative: "Creative"
        case .technical: "Technical"
        }
    }

    /// SF Symbol name for the goal mode card icon.
    var icon: String {
        switch self {
        case .academic: "graduationcap.fill"
        case .business: "briefcase.fill"
        case .casual: "bubble.left.fill"
        case .creative: "paintbrush.fill"
        case .technical: "terminal.fill"
        }
    }

    /// Short one-liner shown in the goals card.
    var shortDescription: String {
        switch self {
        case .academic: "Essays, research papers, and formal writing"
        case .business: "Emails, reports, and professional documents"
        case .casual: "Chats, blogs, and personal notes"
        case .creative: "Stories, poems, and imaginative writing"
        case .technical: "Documentation, code comments, and specs"
        }
    }

    /// Full description passed to the LLM system prompt.
    var systemDescription: String {
        switch self {
        case .academic:
            "formal academic writing — enforce grammar rules strictly, flag passive voice, prefer precise vocabulary"
        case .business:
            "professional business writing — clear, concise, direct; avoid jargon and filler words"
        case .casual:
            "everyday conversational writing — light touch, preserve voice, fix clear errors only"
        case .creative:
            "creative or narrative writing — minimal interference, fix spelling/punctuation only, preserve stylistic choices"
        case .technical:
            "technical documentation — precise terminology, imperative voice preferred, skip creative style suggestions"
        }
    }
}
