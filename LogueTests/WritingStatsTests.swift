import Foundation
@testable import Logue
import Testing

@Suite("WritingStats")
struct WritingStatsTests {
    // MARK: - Word Count

    @Test("Word count is correct for standard text")
    func wordCountStandard() {
        let stats = WritingStats.compute(from: "Hello world test")
        #expect(stats.wordCount == 3)
    }

    @Test("Word count ignores punctuation attached to words")
    func wordCountWithPunctuation() {
        let stats = WritingStats.compute(from: "Hello, world! It's a test.")
        #expect(stats.wordCount == 5)
    }

    // MARK: - Sentence Count

    @Test("Sentence count splits correctly")
    func sentenceCountStandard() {
        let stats = WritingStats.compute(from: "Hello world. This is a test! Wait, another sentence?")
        #expect(stats.sentenceCount == 3)
    }

    @Test("Handles multiple punctuations as one break")
    func sentenceCountMultiplePunctuations() {
        let stats = WritingStats.compute(from: "What?! No way...")
        #expect(stats.sentenceCount == 2)
    }

    // MARK: - Paragraph Count

    @Test("Paragraph count splits on double newlines")
    func paragraphCountStandard() {
        let stats = WritingStats.compute(from: "Paragraph one.\n\nParagraph two.\n\nParagraph three.")
        #expect(stats.paragraphCount == 3)
    }

    @Test("Paragraph ignores single newlines")
    func paragraphCountSingleNewlines() {
        let stats = WritingStats.compute(from: "Line one.\nLine two.")
        #expect(stats.paragraphCount == 1)
    }

    // MARK: - Empty Cases

    @Test("Returns empty stats for empty string")
    func emptyString() {
        let stats = WritingStats.compute(from: "")
        #expect(stats.wordCount == 0)
        #expect(stats.sentenceCount == 0)
        #expect(stats.paragraphCount == 0)
        #expect(stats.avgWordsPerSentence == 0)
        #expect(stats.fleschReadingEase == 0)
        #expect(stats.fleschKincaidGrade == 0)
    }

    @Test("Returns empty stats for whitespaces")
    func whitespaceString() {
        let stats = WritingStats.compute(from: "   \n  \t ")
        #expect(stats.wordCount == 0)
    }

    // MARK: - Formulas

    @Test("Flesch score is within valid range")
    func fleschRange() {
        let text = "The cat sat on the mat. It was a nice day."
        let stats = WritingStats.compute(from: text)
        #expect(stats.fleschReadingEase >= 0)
        #expect(stats.fleschReadingEase <= 100)
    }

    @Test("Flesch-Kincaid Grade Level evaluates appropriately")
    func gradeLevel() {
        // Simple text should have low grade
        let simpleText = "See Spot run. Run, Spot, run!"
        let simpleStats = WritingStats.compute(from: simpleText)

        // Complex text should have higher grade
        let complexText = "The socioeconomic implications of contemporary geopolitical paradigms paradoxically juxtapose traditional methodologies."
        let complexStats = WritingStats.compute(from: complexText)

        #expect(complexStats.fleschKincaidGrade > simpleStats.fleschKincaidGrade)
    }
}
