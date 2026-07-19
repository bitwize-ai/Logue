import Foundation

/// Writing statistics computed locally in Swift — no LLM required.
struct WritingStats: Sendable {
    let wordCount: Int
    let sentenceCount: Int
    let paragraphCount: Int
    let avgWordsPerSentence: Double
    /// Flesch Reading Ease score (0–100; higher = easier to read).
    let fleschReadingEase: Double
    /// Flesch-Kincaid Grade Level.
    let fleschKincaidGrade: Double

    static let empty = WritingStats(
        wordCount: 0,
        sentenceCount: 0,
        paragraphCount: 0,
        avgWordsPerSentence: 0,
        fleschReadingEase: 0,
        fleschKincaidGrade: 0
    )
}

// MARK: - Local Computation

extension WritingStats {
    /// Computes writing stats from plain text. Pure Swift, O(n).
    static func compute(from text: String) -> WritingStats {
        guard !text.isEmpty else { return .empty }

        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let wordCount = words.count

        // Sentences: split on . ! ?  (rough heuristic)
        let sentencePattern = #/[.!?]+\s+|[.!?]+$/#
        let sentences = text.split(separator: sentencePattern, maxSplits: .max)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let sentenceCount = max(sentences.count, 1)

        let paragraphs = text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let paragraphCount = max(paragraphs.count, 1)

        let avgWordsPerSentence = Double(wordCount) / Double(sentenceCount)

        // Syllable count: simple heuristic — count vowel groups per word
        let syllableCount = words.reduce(0) { $0 + countSyllables(in: $1) }
        let avgSyllablesPerWord = wordCount > 0
            ? Double(syllableCount) / Double(wordCount)
            : 0

        // Flesch Reading Ease = 206.835 − 1.015×(words/sentences) − 84.6×(syllables/words)
        let readingEase = 206.835
            - 1.015 * avgWordsPerSentence
            - 84.6 * avgSyllablesPerWord

        // Flesch-Kincaid Grade = 0.39×(words/sentences) + 11.8×(syllables/words) − 15.59
        let gradeLevel = 0.39 * avgWordsPerSentence
            + 11.8 * avgSyllablesPerWord
            - 15.59

        return WritingStats(
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            paragraphCount: paragraphCount,
            avgWordsPerSentence: avgWordsPerSentence,
            fleschReadingEase: max(0, min(100, readingEase)),
            fleschKincaidGrade: max(0, gradeLevel)
        )
    }

    /// Rough syllable counter: count runs of vowels per word.
    private static func countSyllables(in word: String) -> Int {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "A", "E", "I", "O", "U"]
        var count = 0
        var prevWasVowel = false
        for char in word {
            let isVowel = vowels.contains(char)
            if isVowel, !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }
        // Silent trailing 'e'
        if word.count > 2, word.last?.lowercased() == "e", count > 1 {
            count -= 1
        }
        return max(1, count)
    }
}
