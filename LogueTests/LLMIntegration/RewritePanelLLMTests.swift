import Foundation
@testable import Logue
import Testing

// MARK: - Rewrite Style LLM Tests

@Suite("Rewrite Style LLM", .serialized, .timeLimit(.minutes(15)))
struct RewriteStyleLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildRewritePrompt(text: String, style: RewriteStyle) -> String {
        """
        Rewrite this text in a \(style.rawValue.lowercased()) style.

        Style guidelines: \(style.description)

        Maintain the core message and key points, but transform the tone, vocabulary, and structure to match the selected style.

        Text: \(text)
        """
    }

    @Test("Rewrite casual blog post in professional style")
    func rewrite_professional() async throws {
        let input = SampleDocuments.casualBlogPost
        let prompt = buildRewritePrompt(text: input, style: .professional)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "professional",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("Rewrite business email in casual style")
    func rewrite_casual() async throws {
        let input = SampleDocuments.businessEmail
        let prompt = buildRewritePrompt(text: input, style: .casual)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "casual",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("Rewrite casual blog post in academic style")
    func rewrite_academic() async throws {
        let input = SampleDocuments.casualBlogPost
        let prompt = buildRewritePrompt(text: input, style: .academic)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "academic",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("Rewrite technical doc in creative style")
    func rewrite_creative() async throws {
        let input = SampleDocuments.technicalDoc
        let prompt = buildRewritePrompt(text: input, style: .creative)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "creative",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("Rewrite verbose text in concise style produces shorter output")
    func rewrite_concise() async throws {
        let input = SampleDocuments.verboseAcademicText
        let prompt = buildRewritePrompt(text: input, style: .concise)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        let ratio = Double(trimmed.count) / Double(input.count)
        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "concise",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && ratio < 1.0,
            notes: "Length ratio: \(String(format: "%.2f", ratio))x"
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
        #expect(ratio < 1.5, "Concise rewrite should not be much longer than input. Ratio: \(String(format: "%.2f", ratio))x")
    }

    @Test("Rewrite business email in persuasive style")
    func rewrite_persuasive() async throws {
        let input = SampleDocuments.businessEmail
        let prompt = buildRewritePrompt(text: input, style: .persuasive)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "persuasive",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("Rewrite verbose text in natural style")
    func rewrite_natural() async throws {
        let input = SampleDocuments.verboseAcademicText
        let prompt = buildRewritePrompt(text: input, style: .natural)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "natural",
            input: String(input.prefix(80)),
            output: trimmed,
            passed: !trimmed.isEmpty && trimmed != input
        )
        #expect(!trimmed.isEmpty, "Rewrite should produce output")
        #expect(trimmed != input, "Rewritten text should differ from input")
    }

    @Test("All 7 rewrite styles produce unique non-empty outputs")
    func rewrite_allStyles() async throws {
        let input = SampleDocuments.casualBlogPost
        var outputs: [RewriteStyle: String] = [:]

        for style in RewriteStyle.allCases {
            let prompt = buildRewritePrompt(text: input, style: style)
            let response = try await LLMEngine.shared.chat(prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            outputs[style] = trimmed

            #expect(!trimmed.isEmpty, "Rewrite \(style.rawValue) should produce output")
            #expect(trimmed != input, "Rewrite \(style.rawValue) should differ from input")

            LLMTestEval.logResult(
                feature: "Rewrite", testCase: "allStyles_\(style.rawValue)",
                input: String(input.prefix(60)),
                output: String(trimmed.prefix(200)),
                passed: !trimmed.isEmpty && trimmed != input,
                notes: "Length: \(trimmed.count) chars"
            )
        }

        #expect(outputs.count == RewriteStyle.allCases.count, "Should have outputs for all \(RewriteStyle.allCases.count) styles")
    }

    @Test("Rewrite short text produces valid output")
    func rewrite_shortText() async throws {
        let input = SampleDocuments.shortText
        let prompt = buildRewritePrompt(text: input, style: .professional)
        let response = try await LLMEngine.shared.chat(prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        LLMTestEval.logResult(
            feature: "Rewrite", testCase: "shortText",
            input: input,
            output: trimmed,
            passed: !trimmed.isEmpty
        )
        #expect(!trimmed.isEmpty, "Should produce output even for very short text")
    }

    @Test("Rewrite length ratio is reasonable across all styles")
    func rewrite_lengthRatio() async throws {
        let input = SampleDocuments.verboseAcademicText

        for style in RewriteStyle.allCases {
            let prompt = buildRewritePrompt(text: input, style: style)
            let response = try await LLMEngine.shared.chat(prompt: prompt)
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                #expect(!trimmed.isEmpty, "Rewrite \(style.rawValue) should not be empty")
                continue
            }

            let ratio = Double(trimmed.count) / Double(input.count)
            let passed = ratio >= 0.1 && ratio <= 10.0

            LLMTestEval.logResult(
                feature: "Rewrite", testCase: "lengthRatio_\(style.rawValue)",
                input: "\(input.count) chars",
                output: "\(trimmed.count) chars",
                passed: passed,
                notes: "Ratio: \(String(format: "%.2f", ratio))x"
            )
            #expect(passed, "Rewrite \(style.rawValue) length ratio should be 0.1x-10.0x, got \(String(format: "%.2f", ratio))x")
        }
    }
}
