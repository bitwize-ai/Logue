import SwiftUI

// MARK: - ReviewTab

enum ReviewTab: String, CaseIterable {
    case score = "Score"
    case reactions = "Reactions"

    var icon: String {
        switch self {
        case .score: "chart.bar.fill"
        case .reactions: "face.smiling.fill"
        }
    }
}

// MARK: - RubricCategory

enum RubricCategory: String, CaseIterable, Identifiable, Codable {
    case thesis = "Thesis"
    case evidence = "Evidence"
    case organization = "Organization"
    case style = "Style"
    case grammar = "Grammar"
    case clarity = "Clarity"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .thesis: "lightbulb.fill"
        case .evidence: "chart.bar.fill"
        case .organization: "list.bullet.rectangle"
        case .style: "paintbrush.fill"
        case .grammar: "textformat.abc"
        case .clarity: "eye.fill"
        }
    }

    var description: String {
        switch self {
        case .thesis: "Central argument strength and clarity"
        case .evidence: "Quality and relevance of supporting details"
        case .organization: "Structure, flow, and coherence"
        case .style: "Writing voice, tone, and engagement"
        case .grammar: "Correctness and technical accuracy"
        case .clarity: "Readability and comprehension"
        }
    }

    var color: Color {
        switch self {
        case .thesis: AppThemeConstants.categoryPurple
        case .evidence: AppThemeConstants.brandPrimary
        case .organization: AppThemeConstants.success
        case .style: AppThemeConstants.warning
        case .grammar: AppThemeConstants.error
        case .clarity: AppThemeConstants.brandPrimary
        }
    }
}

// MARK: - Grade

struct Grade: Identifiable, Codable {
    let id: UUID
    let category: RubricCategory
    let score: Int
    let letterGrade: String
    let feedback: String
    let strengths: [String]
    let improvements: [String]

    init(
        id: UUID = UUID(),
        category: RubricCategory,
        score: Int,
        letterGrade: String,
        feedback: String,
        strengths: [String],
        improvements: [String]
    ) {
        self.id = id
        self.category = category
        self.score = score
        self.letterGrade = letterGrade
        self.feedback = feedback
        self.strengths = strengths
        self.improvements = improvements
    }
}

// MARK: - OverallGrade

struct OverallGrade: Codable {
    let averageScore: Int
    let letterGrade: String
    let summary: String
    let grades: [Grade]
}

// MARK: - EmotionType

enum EmotionType: String, CaseIterable, Identifiable, Codable {
    case excited = "Excited"
    case confused = "Confused"
    case skeptical = "Skeptical"
    case engaged = "Engaged"
    case bored = "Bored"
    case inspired = "Inspired"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .excited: "star.fill"
        case .confused: "questionmark.circle.fill"
        case .skeptical: "eyebrow"
        case .engaged: "eye.fill"
        case .bored: "zzz"
        case .inspired: "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .excited: AppThemeConstants.categoryYellow
        case .confused: AppThemeConstants.warning
        case .skeptical: AppThemeConstants.categoryPurple
        case .engaged: AppThemeConstants.success
        case .bored: AppThemeConstants.categoryGray
        case .inspired: AppThemeConstants.brandPrimary
        }
    }
}

// MARK: - SectionReaction

struct SectionReaction: Identifiable, Codable {
    let id: UUID
    let sectionTitle: String
    let sectionText: String
    let dominantEmotion: EmotionType
    let emotionScores: [String: Int]
    let explanation: String

    init(
        id: UUID = UUID(),
        sectionTitle: String,
        sectionText: String,
        dominantEmotion: EmotionType,
        emotionScores: [EmotionType: Int],
        explanation: String
    ) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.sectionText = sectionText
        self.dominantEmotion = dominantEmotion
        // Store as [String: Int] for Codable compatibility
        self.emotionScores = Dictionary(uniqueKeysWithValues: emotionScores.map { ($0.key.rawValue, $0.value) })
        self.explanation = explanation
    }

    /// Access emotion scores using EmotionType keys.
    func score(for emotion: EmotionType) -> Int {
        emotionScores[emotion.rawValue] ?? 0
    }

    /// All emotion scores as typed dictionary.
    var typedEmotionScores: [EmotionType: Int] {
        Dictionary(uniqueKeysWithValues: emotionScores.compactMap { key, value in
            EmotionType(rawValue: key).map { ($0, value) }
        })
    }
}
