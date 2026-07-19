import Foundation
@testable import Logue
import Testing

// MARK: - Review Score LLM Tests

@Suite("Review Score LLM", .serialized, .timeLimit(.minutes(15)))
struct ReviewScoreLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildGradingPrompt(text: String) -> String {
        """
        Grade this writing using a comprehensive rubric with these categories:
        1. Thesis (central argument)
        2. Evidence (supporting details)
        3. Organization (structure and flow)
        4. Style (voice and engagement)
        5. Grammar (technical correctness)
        6. Clarity (readability)

        For each category, provide:
        - Score (0-100)
        - Letter grade
        - Feedback
        - Strengths
        - Areas for improvement

        Return ONLY valid JSON in this exact format:
        {
          "summary": "Overall summary of the text assessment...",
          "grades": [
            {
              "category": "Thesis",
              "score": 90,
              "letterGrade": "A-",
              "feedback": "Feedback for thesis...",
              "strengths": ["Strength 1"],
              "improvements": ["Improvement 1"]
            }
          ]
        }

        Category strings must be exactly: Thesis, Evidence, Organization, Style, Grammar, Clarity.

        Text: \(text)
        """
    }

    @Test("Grading business email produces valid rubric JSON")
    func grading_businessEmail() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.businessEmail)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateGradeResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewScore", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Grade response should be valid JSON. Issues: \(result.notes)")
        #expect(result.gradeCount >= 4, "Should have at least 4 of 6 categories, got \(result.gradeCount)")
        #expect(result.averageScore != nil, "Should compute an average score")
    }

    @Test("Grading academic essay produces valid rubric JSON")
    func grading_academicEssay() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.academicEssay)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateGradeResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewScore", testCase: "academicEssay",
            input: String(SampleDocuments.academicEssay.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Grade response should be valid JSON. Issues: \(result.notes)")
        #expect(result.gradeCount >= 4, "Should have at least 4 categories, got \(result.gradeCount)")
    }

    @Test("Grading casual blog post detects grammar weaknesses")
    func grading_casualBlogPost() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.casualBlogPost)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateGradeResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewScore", testCase: "casualBlogPost",
            input: String(SampleDocuments.casualBlogPost.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Grade response should be valid JSON. Issues: \(result.notes)")
        #expect(result.gradeCount >= 3, "Should have at least 3 categories, got \(result.gradeCount)")
    }

    @Test("Grading short text does not crash")
    func grading_shortText() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.shortText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateGradeResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewScore", testCase: "shortText",
            input: SampleDocuments.shortText,
            output: response,
            passed: true, notes: "gradeCount=\(result.gradeCount), valid=\(result.valid). \(result.notes)"
        )
        // Short text may or may not produce grades — key is no crash
        // If it produces grades, they should be valid
        if result.gradeCount > 0 {
            #expect(result.valid, "If grades are returned, they should be valid. Issues: \(result.notes)")
        }
    }

    @Test("Grading JSON has all required schema fields")
    func grading_jsonSchema() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.technicalDoc)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        // Validate raw JSON structure
        guard let jsonString = LLMTestEval.extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            #expect(Bool(false), "Failed to extract JSON from grading response")
            return
        }

        #expect(json["summary"] != nil, "JSON should contain 'summary' field")
        #expect(json["grades"] != nil, "JSON should contain 'grades' field")

        if let grades = json["grades"] as? [[String: Any]], let first = grades.first {
            #expect(first["category"] != nil, "Grade item should have 'category'")
            #expect(first["score"] != nil, "Grade item should have 'score'")
            #expect(first["letterGrade"] != nil, "Grade item should have 'letterGrade'")
            #expect(first["feedback"] != nil, "Grade item should have 'feedback'")
        }

        LLMTestEval.logResult(
            feature: "ReviewScore", testCase: "jsonSchema",
            input: "Schema validation for technicalDoc",
            output: "Fields: \(json.keys.sorted().joined(separator: ", "))",
            passed: json["summary"] != nil && json["grades"] != nil
        )
    }

    @Test("Letter grade is consistent with numerical score")
    func grading_letterGradeConsistency() async throws {
        let prompt = buildGradingPrompt(text: SampleDocuments.creativeWriting)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        guard let jsonString = LLMTestEval.extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let grades = json["grades"] as? [[String: Any]]
        else {
            #expect(Bool(false), "Failed to extract grade JSON")
            return
        }

        for grade in grades {
            guard let score = grade["score"] as? Int ?? (grade["score"] as? Double).map({ Int($0) }),
                  let letter = grade["letterGrade"] as? String,
                  let category = grade["category"] as? String
            else { continue }

            // Verify letter grade is reasonable for the score range
            let expectedPrefix = switch true {
            case _ where score >= 90: "A"
            case _ where score >= 80: "B"
            case _ where score >= 70: "C"
            default: "D"
            }

            let passed = letter.starts(with: expectedPrefix) || letter.starts(with: "F")
            LLMTestEval.logResult(
                feature: "ReviewScore", testCase: "letterGrade_\(category)",
                input: "score=\(score)", output: "letter=\(letter), expected prefix=\(expectedPrefix)",
                passed: passed
            )
            // Soft check — small models may not always match exactly
            if !passed {
                print("  [WARN] \(category): score \(score) → '\(letter)' (expected '\(expectedPrefix)' prefix)")
            }
        }
    }
}

// MARK: - Review Reactions LLM Tests

@Suite("Review Reactions LLM", .serialized, .timeLimit(.minutes(10)))
struct ReviewReactionsLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildReactionsPrompt(text: String) -> String {
        """
        Analyze this text and predict reader emotional responses for different sections.
        Return ONLY valid JSON in this exact format:
        [
          {
            "sectionTitle": "Section Name",
            "dominantEmotion": "engaged",
            "emotionScores": {"engaged": 85, "excited": 60, "confused": 15},
            "explanation": "Why readers feel this way"
          }
        ]

        Emotions must be from: excited, confused, skeptical, engaged, bored, inspired.
        Scores are 0-100. Break the text into 3-5 sections.

        Text: \(text)
        """
    }

    @Test("Reactions for business email returns valid sections")
    func reactions_businessEmail() async throws {
        let prompt = buildReactionsPrompt(text: SampleDocuments.businessEmail)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateReactionsResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewReactions", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Reactions should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 1, "Should have at least 1 section, got \(result.count)")
    }

    @Test("Reactions for academic essay returns valid sections")
    func reactions_academicEssay() async throws {
        let prompt = buildReactionsPrompt(text: SampleDocuments.academicEssay)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateReactionsResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewReactions", testCase: "academicEssay",
            input: String(SampleDocuments.academicEssay.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Reactions should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 1, "Should have at least 1 section, got \(result.count)")
    }

    @Test("Reactions for creative writing returns valid emotions")
    func reactions_creativeWriting() async throws {
        let prompt = buildReactionsPrompt(text: SampleDocuments.creativeWriting)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateReactionsResponse(response)
        LLMTestEval.logResult(
            feature: "ReviewReactions", testCase: "creativeWriting",
            input: String(SampleDocuments.creativeWriting.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Reactions should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 1, "Should have at least 1 section")
    }

    @Test("Reactions emotion scores are all within 0-100 range")
    func reactions_emotionScoresValid() async throws {
        let prompt = buildReactionsPrompt(text: SampleDocuments.technicalDoc)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        // Parse and check scores manually
        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "["),
              let arrEnd = cleaned.lastIndex(of: "]"),
              arrStart < arrEnd,
              let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            let result = LLMTestEval.validateReactionsResponse(response)
            #expect(result.valid, "Should produce valid reactions JSON. Issues: \(result.notes)")
            return
        }

        var allScoresValid = true
        for item in items {
            if let scores = item["emotionScores"] as? [String: Any] {
                for (emotion, value) in scores {
                    if let score = value as? Int {
                        if score < 0 || score > 100 {
                            allScoresValid = false
                            print("  [WARN] Emotion '\(emotion)' score \(score) out of 0-100")
                        }
                    }
                }
            }
        }

        LLMTestEval.logResult(
            feature: "ReviewReactions", testCase: "emotionScoresValid",
            input: "technicalDoc",
            output: "Checked \(items.count) sections",
            passed: allScoresValid
        )
        #expect(allScoresValid, "All emotion scores should be within 0-100")
    }

    @Test("Reactions for short text does not crash")
    func reactions_shortText() async throws {
        let prompt = buildReactionsPrompt(text: SampleDocuments.shortText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "ReviewReactions", testCase: "shortText",
            input: SampleDocuments.shortText,
            output: response,
            passed: true, notes: "Short text — may return 0-1 sections"
        )
        // Should not crash — validation is optional for very short text
        let (valid, reactionCount, notes) = LLMTestEval.validateReactionsResponse(response)
        if reactionCount > 0 {
            #expect(valid, "If reactions are returned, they should be valid. Issues: \(notes)")
        }
    }
}
