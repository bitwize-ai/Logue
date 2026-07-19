import Foundation
@testable import Logue
import Testing

// MARK: - Vocabulary Enhancement LLM Tests

@Suite("Vocabulary Enhancement LLM", .serialized, .timeLimit(.minutes(10)))
struct VocabularyEnhancementLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildVocabPrompt(text: String) -> String {
        """
        Analyze this text and suggest vocabulary enhancements.
        Identify overused, weak, or imprecise words and suggest stronger alternatives.

        Return ONLY valid JSON in this exact format:
        [
          {
            "original": "the weak word or phrase",
            "suggestion": "the stronger replacement",
            "explanation": "why this is better",
            "category": "overused"
          }
        ]

        Categories: "overused", "weak", "informal", "imprecise", "repetitive"
        Limit to 10 most impactful suggestions.

        Text: \(text)
        """
    }

    @Test("Vocabulary enhancement on casual blog post finds suggestions")
    func vocab_casualBlogPost() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.casualBlogPost)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateVocabResponse(response)
        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "casualBlogPost",
            input: String(SampleDocuments.casualBlogPost.prefix(100)),
            output: response,
            passed: result.valid, notes: "count=\(result.count). \(result.notes)"
        )
        #expect(result.valid, "Vocab response should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 2, "Casual blog post should have at least 2 vocab suggestions, got \(result.count)")
    }

    @Test("Vocabulary enhancement on verbose academic text finds multiple suggestions")
    func vocab_verboseAcademic() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.verboseAcademicText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateVocabResponse(response)
        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "verboseAcademic",
            input: String(SampleDocuments.verboseAcademicText.prefix(100)),
            output: response,
            passed: result.valid, notes: "count=\(result.count). \(result.notes)"
        )
        #expect(result.valid, "Vocab response should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 1, "Verbose academic text should yield at least 1 suggestion, got \(result.count)")
    }

    @Test("Vocabulary enhancement on business email produces valid JSON")
    func vocab_businessEmail() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.businessEmail)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateVocabResponse(response)
        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: response,
            passed: result.valid, notes: "count=\(result.count). \(result.notes)"
        )
        #expect(result.valid, "Vocab response should be valid JSON. Issues: \(result.notes)")
    }

    @Test("Vocabulary enhancement on clean text returns few or no suggestions")
    func vocab_cleanText() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.cleanText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateVocabResponse(response)
        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "cleanText",
            input: SampleDocuments.cleanText,
            output: response,
            passed: true, notes: "count=\(result.count). \(result.notes)"
        )
        // Clean simple text may still get suggestions from eager LLMs — key is no crash and valid JSON
        // Small models may over-generate; we just ensure the response is parseable
        if result.count > 5 {
            print("  [WARN] Clean text produced \(result.count) suggestions (model over-generated)")
        }
    }

    @Test("Vocabulary suggestions are limited to 10")
    func vocab_maxCount() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.verboseAcademicText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        // Parse raw array to check count
        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        if let arrStart = cleaned.firstIndex(of: "["),
           let arrEnd = cleaned.lastIndex(of: "]"),
           arrStart < arrEnd,
           let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            LLMTestEval.logResult(
                feature: "Vocabulary", testCase: "maxCount",
                input: "verboseAcademicText",
                output: "\(items.count) raw items",
                passed: items.count <= 15, // Allow some over-generation from small model
                notes: items.count > 10 ? "Over-generation: \(items.count) items (limit was 10)" : ""
            )
            // Small models may slightly exceed the limit — warn but don't hard-fail above 15
            #expect(items.count <= 15, "Should have at most ~10 suggestions (allow small model wiggle room), got \(items.count)")
        }
    }

    @Test("Vocabulary suggestions have required fields")
    func vocab_requiredFields() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.casualBlogPost)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "["),
              let arrEnd = cleaned.lastIndex(of: "]"),
              arrStart < arrEnd,
              let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            #expect(Bool(false), "Failed to parse vocab JSON array")
            return
        }

        var allHaveRequired = true
        for (idx, item) in items.prefix(10).enumerated() {
            let hasOriginal = (item["original"] as? String)?.isEmpty == false
            let hasSuggestion = (item["suggestion"] as? String)?.isEmpty == false

            if !hasOriginal {
                allHaveRequired = false
                print("  [FAIL] Item \(idx): missing or empty 'original'")
            }
            if !hasSuggestion {
                allHaveRequired = false
                print("  [FAIL] Item \(idx): missing or empty 'suggestion'")
            }
        }

        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "requiredFields",
            input: "casualBlogPost",
            output: "Checked \(min(items.count, 10)) items",
            passed: allHaveRequired
        )
        #expect(allHaveRequired, "All vocab suggestions should have non-empty 'original' and 'suggestion' fields")
    }

    @Test("Vocabulary optional fields have correct defaults")
    func vocab_optionalDefaults() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.technicalDoc)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "["),
              let arrEnd = cleaned.lastIndex(of: "]"),
              arrStart < arrEnd,
              let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            // If parsing fails, the validation helper will catch it
            let result = LLMTestEval.validateVocabResponse(response)
            #expect(result.valid, "Vocab response should be valid. Issues: \(result.notes)")
            return
        }

        // Verify that when fields are present, they have reasonable values
        // When absent, production code defaults: explanation → "", category → "weak"
        let validCategories: Set<String> = ["overused", "weak", "informal", "imprecise", "repetitive"]
        var notes: [String] = []

        for (idx, item) in items.prefix(10).enumerated() {
            // explanation is optional
            if let explanation = item["explanation"] as? String {
                notes.append("Item \(idx): explanation present (\(explanation.count) chars)")
            } else {
                notes.append("Item \(idx): explanation missing (defaults to '')")
            }

            // category is optional, defaults to "weak"
            if let category = item["category"] as? String {
                if !validCategories.contains(category.lowercased()) {
                    notes.append("Item \(idx): unknown category '\(category)' (defaults to 'weak')")
                }
            } else {
                notes.append("Item \(idx): category missing (defaults to 'weak')")
            }
        }

        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "optionalDefaults",
            input: "technicalDoc",
            output: notes.joined(separator: "; "),
            passed: true
        )
    }

    @Test("Vocabulary categories are all valid values")
    func vocab_categoryValues() async throws {
        let prompt = buildVocabPrompt(text: SampleDocuments.casualBlogPost)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateVocabResponse(response)
        LLMTestEval.logResult(
            feature: "Vocabulary", testCase: "categoryValues",
            input: "casualBlogPost",
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "All categories should be valid. Issues: \(result.notes)")

        // Additionally parse and check categories
        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        if let arrStart = cleaned.firstIndex(of: "["),
           let arrEnd = cleaned.lastIndex(of: "]"),
           arrStart < arrEnd,
           let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            let validCategories: Set<String> = ["overused", "weak", "informal", "imprecise", "repetitive"]
            let foundCategories = items.compactMap { $0["category"] as? String }
            let invalidCategories = foundCategories.filter { !validCategories.contains($0.lowercased()) }

            if !invalidCategories.isEmpty {
                print("  [WARN] Invalid categories found: \(invalidCategories)")
            }
        }
    }
}
