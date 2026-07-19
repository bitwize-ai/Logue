import Foundation
@testable import Logue
import Testing

@Suite("WritingScore")
struct WritingScoreTests {
    // MARK: - Compute Score

    @Test("Perfect score for no issues")
    func perfectScore() {
        let score = WritingScore.compute(grammarCount: 0, clarityCount: 0, wordCount: 200)

        #expect(score.correctness == 100.0)
        #expect(score.clarity == 100.0)
        #expect(score.engagement == 80.0) // wordCount > 100 -> 80
        #expect(score.delivery == 82.0)

        // 100*0.40 + 100*0.25 + 80*0.20 + 82*0.15 = 40 + 25 + 16 + 12.3 = 93.3
        #expect(score.overall == 93.3)
    }

    @Test("Correctness drops correctly but doesn't go below 50")
    func correctnessDrop() {
        let oneIssue = WritingScore.compute(grammarCount: 1, clarityCount: 0, wordCount: 50)
        #expect(oneIssue.correctness == 90.0)

        let tenIssues = WritingScore.compute(grammarCount: 10, clarityCount: 0, wordCount: 50)
        #expect(tenIssues.correctness == 50.0) // Hit floor
    }

    @Test("Clarity drops correctly but doesn't go below 50")
    func clarityDrop() {
        let oneIssue = WritingScore.compute(grammarCount: 0, clarityCount: 1, wordCount: 50)
        #expect(oneIssue.clarity == 88.0) // 100 - 12

        let tenIssues = WritingScore.compute(grammarCount: 0, clarityCount: 10, wordCount: 50)
        #expect(tenIssues.clarity == 50.0) // Hit floor
    }

    @Test("Clarity handles quick mode properly (nil = not analysed)")
    func clarityQuickMode() {
        // Quick mode passes clarityCount == nil because clarity check wasn't run
        let score = WritingScore.compute(grammarCount: 0, clarityCount: nil, wordCount: 50)
        #expect(score.clarity == 85.0)
    }

    // MARK: - Letter Grade

    @Test("Letter grade correctly maps from overall score")
    func letterGrades() {
        var score = WritingScore.empty

        score.overall = 95
        #expect(score.letter == "A")

        score.overall = 90
        #expect(score.letter == "A")

        score.overall = 89.9
        #expect(score.letter == "B")

        score.overall = 80
        #expect(score.letter == "B")

        score.overall = 75
        #expect(score.letter == "C")

        score.overall = 65
        #expect(score.letter == "D")

        score.overall = 50
        #expect(score.letter == "F")

        score.overall = 0
        #expect(score.letter == "F")
    }
}
