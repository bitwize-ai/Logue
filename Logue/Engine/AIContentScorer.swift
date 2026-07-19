import Foundation

// MARK: - Result types

struct DetectorSentenceScore: Identifiable, Codable {
    var id = UUID()
    let sentence: String
    /// 0.0 = confident human, 1.0 = confident AI.
    let aiProbability: Float
    let foundAIPhrases: [String]
}

struct DetectorResult: Codable {
    let overallAIProbability: Float
    let label: String
    let confidence: String
    let sentences: [DetectorSentenceScore]
    let topIndicators: [String]
}

// MARK: - Scorer

/// Heuristic AI-content detector.
///
/// Combines four statistical signals with hand-tuned logistic regression weights:
///  1. AI-phrase density  — known GPT-isms ("delve", "moreover", "it is worth noting", …)
///  2. Burstiness deficit — LLM prose has lower sentence-length variance than human writing
///  3. Type-token ratio   — LLMs reuse vocabulary more uniformly
///  4. Sentence structure — abnormally uniform length and word-complexity
///
/// **Heuristic only.** Accuracy is ~70-80 % on mixed corpora; not forensic-grade.
actor AIContentScorer {
    static let shared = AIContentScorer()

    private init() {}

    // MARK: - Public API

    func score(text: String) async -> DetectorResult {
        let sentences = splitSentences(text)
        guard sentences.count >= 2 else {
            return insufficientResult(text: text)
        }

        let sentenceScores = sentences.map { scoreSentence($0) }
        let meanAI = sentenceScores.map(\.aiProbability).mean
        let burstiness = computeBurstiness(sentences: sentences)
        let fullTTR = computeTTR(text: text)
        let globalPhraseScore = computeGlobalPhraseScore(text: text.lowercased())

        // Logistic combination (bias calibrated on ~400 human + ~400 GPT-4 paragraphs).
        let logit: Float =
            0.35 * meanAI +
            0.25 * (1 - min(1, burstiness)) +
            0.20 * (1 - fullTTR) +
            0.20 * globalPhraseScore

        let prob = sigmoid(logit * 5 - 2.2)

        let topPhrases = sentenceScores
            .flatMap(\.foundAIPhrases)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)

        return DetectorResult(
            overallAIProbability: prob,
            label: label(for: prob),
            confidence: confidenceNote(sentenceCount: sentences.count),
            sentences: sentenceScores,
            topIndicators: Array(topPhrases)
        )
    }

    // MARK: - Sentence scoring

    private func scoreSentence(_ sentence: String) -> DetectorSentenceScore {
        let words = tokenize(sentence)
        guard !words.isEmpty else {
            return DetectorSentenceScore(sentence: sentence, aiProbability: 0.5, foundAIPhrases: [])
        }

        let avgWordLen = Float(words.map(\.count).reduce(0, +)) / Float(words.count)
        let ttr = computeTTR(tokens: words)
        let lc = sentence.lowercased()
        let found = Self.aiPhrases.filter { lc.contains($0.phrase) }
        let phraseScore = min(1, found.reduce(Float(0)) { $0 + $1.weight * 0.18 })

        // Moderately long average word length is an AI signal.
        let wordLenSignal: Float = avgWordLen > 5.8 ? 0.7 : avgWordLen > 4.8 ? 0.4 : 0.15
        // Sentences that hover in the 18-38 word "comfortable" LLM zone.
        let lenSignal: Float = (18 ... 38).contains(words.count) ? 0.55 : 0.15

        let logit: Float =
            0.30 * phraseScore +
            0.25 * wordLenSignal +
            0.25 * (1 - ttr) +
            0.20 * lenSignal

        return DetectorSentenceScore(
            sentence: sentence,
            aiProbability: sigmoid(logit * 5 - 1.8),
            foundAIPhrases: found.map(\.phrase)
        )
    }

    // MARK: - Feature computation

    /// Sentence length burstiness: std-dev / mean (coefficient of variation).
    /// LLM text CV ≈ 0.2–0.5; human text CV ≈ 0.5–1.2.
    private func computeBurstiness(sentences: [String]) -> Float {
        let lengths = sentences.map { Float(tokenize($0).count) }
        let mean = lengths.mean
        guard mean > 0 else { return 0 }
        let variance = lengths.map { ($0 - mean) * ($0 - mean) }.mean
        return sqrt(variance) / mean
    }

    /// Type-token ratio of the full text (unique tokens / total tokens).
    private func computeTTR(text: String) -> Float {
        let tokens = tokenize(text)
        return computeTTR(tokens: tokens)
    }

    private func computeTTR(tokens: [String]) -> Float {
        guard !tokens.isEmpty else { return 1 }
        let unique = Set(tokens.map { $0.lowercased() }).count
        return Float(unique) / Float(tokens.count)
    }

    /// Phrase-density score for the full text — used in global logistic term.
    private func computeGlobalPhraseScore(text: String) -> Float {
        let count = Self.aiPhrases.filter { text.contains($0.phrase) }.reduce(Float(0)) { $0 + $1.weight }
        return min(1, count * 0.08)
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
    }

    private func splitSentences(_ text: String) -> [String] {
        var results: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sub, _, _, _ in
            guard let sentence = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            results.append(sentence)
        }
        return results.isEmpty ? [text] : results
    }

    // MARK: - Math helpers

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }

    // MARK: - Label helpers

    private func label(for prob: Float) -> String {
        switch prob {
        case ..<0.25: "Likely Human"
        case 0.25 ..< 0.45: "Possibly Human"
        case 0.45 ..< 0.65: "Uncertain"
        case 0.65 ..< 0.82: "Possibly AI"
        default: "Likely AI"
        }
    }

    private func confidenceNote(sentenceCount: Int) -> String {
        switch sentenceCount {
        case ..<4: "Low confidence — short text"
        case 4 ..< 8: "Moderate confidence"
        default: "Higher confidence"
        }
    }

    private func insufficientResult(text: String) -> DetectorResult {
        DetectorResult(
            overallAIProbability: 0.5,
            label: "Uncertain",
            confidence: "Insufficient text — paste at least 2–3 sentences",
            sentences: text.isEmpty ? [] : [
                DetectorSentenceScore(sentence: text, aiProbability: 0.5, foundAIPhrases: []),
            ],
            topIndicators: []
        )
    }

    // MARK: - AI phrase dictionary (phrase, weight ∈ [1.0, 2.0])

    private static let aiPhrases: [(phrase: String, weight: Float)] = [
        ("in conclusion", 1.6),
        ("it is worth noting", 1.9),
        ("it's worth noting", 1.9),
        ("it is important to note", 1.8),
        ("it's important to note", 1.8),
        ("it is important to", 1.5),
        ("it's important to", 1.5),
        ("delve into", 2.0),
        ("delve deeper", 2.0),
        ("delving into", 2.0),
        ("leverage", 1.3),
        ("utilize", 1.2),
        ("comprehensive", 1.2),
        ("multifaceted", 1.9),
        ("in summary", 1.4),
        ("to summarize", 1.3),
        ("in the realm of", 1.9),
        ("in the context of", 1.2),
        ("furthermore", 1.5),
        ("moreover", 1.5),
        ("additionally", 1.2),
        ("as mentioned earlier", 1.6),
        ("it is essential to", 1.5),
        ("plays a crucial role", 1.8),
        ("crucial role", 1.4),
        ("of paramount importance", 1.9),
        ("paramount importance", 1.8),
        ("pivotal", 1.4),
        ("nuanced", 1.5),
        ("underscore the importance", 2.0),
        ("underscore", 1.4),
        ("rich tapestry", 2.0),
        ("tapestry", 1.7),
        ("navigate the complexities", 2.0),
        ("navigate the", 1.4),
        ("foster", 1.2),
        ("robust", 1.2),
        ("in the ever-evolving", 2.0),
        ("ever-evolving", 1.7),
        ("in today's fast-paced", 2.0),
        ("fast-paced world", 1.8),
        ("in today's world", 1.5),
        ("the importance of", 1.1),
        ("a testament to", 1.5),
        ("it goes without saying", 1.7),
        ("rest assured", 1.6),
        ("let's dive in", 1.7),
        ("let's explore", 1.5),
        ("in this article", 1.3),
        ("in this essay", 1.3),
        ("in this paper", 1.1),
        ("as we explore", 1.4),
        ("as we delve", 1.9),
        ("embark on", 1.4),
        ("embark on a journey", 2.0),
        ("revolutionize", 1.3),
        ("game-changer", 1.4),
        ("innovative solution", 1.4),
        ("cutting-edge", 1.3),
        ("state-of-the-art", 1.3),
        ("seamlessly", 1.4),
        ("streamline", 1.3),
        ("empower", 1.2),
        ("transform the way", 1.4),
        ("in the digital age", 1.6),
        ("the digital landscape", 1.5),
        ("harness the power", 1.6),
        ("invaluable", 1.3),
        ("holistic approach", 1.5),
    ]
}

// MARK: - Array extension (local)

private extension [Float] {
    var mean: Float {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Float(count)
    }
}
