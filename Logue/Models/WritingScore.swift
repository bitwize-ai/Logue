import Foundation

/// Composite writing quality score matching Grammarly's four-category model.
struct WritingScore: Codable, Equatable, Sendable {
    /// Overall composite score 0–100.
    var overall: Double
    /// Grammar, spelling, punctuation correctness 0–100.
    var correctness: Double
    /// Clarity and conciseness 0–100.
    var clarity: Double
    /// Vocabulary variety and engagement 0–100.
    var engagement: Double
    /// Tone match and delivery 0–100.
    var delivery: Double

    static let empty = WritingScore(overall: 0, correctness: 0, clarity: 0, engagement: 0, delivery: 0)

    /// Derives a score from the results of a LangGraph analysis run.
    static func compute(
        grammarCount: Int,
        clarityCount: Int?,
        wordCount: Int
    ) -> WritingScore {
        // Correctness: 100 − 10 per grammar/spelling issue, min 50
        let correctness = max(50.0, 100.0 - Double(grammarCount) * 10.0)
        // Clarity: 100 − 12 per clarity issue (or 85 if not analysed)
        let clarity: Double = if let clarityCount {
            max(50.0, 100.0 - Double(clarityCount) * 12.0)
        } else {
            85.0
        }
        // Engagement and delivery are currently heuristic placeholders
        let engagement = wordCount > 100 ? 80.0 : 75.0
        let delivery = 82.0
        let overall = correctness * 0.40 + clarity * 0.25 + engagement * 0.20 + delivery * 0.15
        return WritingScore(
            overall: overall,
            correctness: correctness,
            clarity: clarity,
            engagement: engagement,
            delivery: delivery
        )
    }

    var letter: String {
        switch overall {
        case 90 ... 100: "A"
        case 80 ..< 90: "B"
        case 70 ..< 80: "C"
        case 60 ..< 70: "D"
        default: "F"
        }
    }
}
