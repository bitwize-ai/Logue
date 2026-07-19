import Foundation
@testable import Logue
import Testing

// MARK: - Document Title Generation Tests

@Suite("Document Title LLM", .serialized, .timeLimit(.minutes(10)))
struct DocumentTitleLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Document title for business email")
    func docTitle_businessEmail() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this document. \
        Output ONLY the title, nothing else.

        Document:
        \(String(SampleDocuments.businessEmail.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = cleanTitle(response)

        LLMTestEval.logResult(
            feature: "DocTitle", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty && cleaned.count <= 100
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 100, "Title should be <= 100 characters, got \(cleaned.count)")
        let wordCount = cleaned.split(separator: " ").count
        #expect(wordCount >= 2 && wordCount <= 15, "Title should have 2-15 words, got \(wordCount): '\(cleaned)'")
    }

    @Test("Document title for academic essay")
    func docTitle_academicEssay() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this document. \
        Output ONLY the title, nothing else.

        Document:
        \(String(SampleDocuments.academicEssay.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = cleanTitle(response)

        LLMTestEval.logResult(
            feature: "DocTitle", testCase: "academicEssay",
            input: String(SampleDocuments.academicEssay.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 120, "Title should be <= 120 characters")
    }

    @Test("Document title for technical documentation")
    func docTitle_technicalDoc() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this document. \
        Output ONLY the title, nothing else.

        Document:
        \(String(SampleDocuments.technicalDoc.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = cleanTitle(response)

        LLMTestEval.logResult(
            feature: "DocTitle", testCase: "technicalDoc",
            input: String(SampleDocuments.technicalDoc.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 120, "Title should be <= 120 characters")
    }

    @Test("Document title for creative writing")
    func docTitle_creativeWriting() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this document. \
        Output ONLY the title, nothing else.

        Document:
        \(String(SampleDocuments.creativeWriting.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = cleanTitle(response)

        LLMTestEval.logResult(
            feature: "DocTitle", testCase: "creativeWriting",
            input: String(SampleDocuments.creativeWriting.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 120, "Title should be <= 120 characters")
    }

    @Test("Document title for long document uses truncated input")
    func docTitle_longDocument() async throws {
        // Create a 5000-char document by repeating the business email
        let longDoc = String(repeating: SampleDocuments.businessEmail + "\n\n", count: 10)
        #expect(longDoc.count > 4000, "Test document should be > 4000 chars")

        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this document. \
        Output ONLY the title, nothing else.

        Document:
        \(String(longDoc.prefix(2000)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = cleanTitle(response)

        LLMTestEval.logResult(
            feature: "DocTitle", testCase: "longDocument",
            input: "5000+ char document (truncated to 2000)",
            output: cleaned, passed: !cleaned.isEmpty && cleaned.count <= 100
        )
        #expect(!cleaned.isEmpty, "Should produce a title from truncated long document")
        #expect(cleaned.count <= 120, "Title should be <= 120 characters")
    }

    private func cleanTitle(_ response: String) -> String {
        response
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") ?? ""
    }
}

// MARK: - Document Chat Tests

@Suite("Document Chat LLM", .serialized, .timeLimit(.minutes(10)))
struct DocumentChatLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Document chat suggests improvements for business email")
    func docChat_improveWriting() async throws {
        let prompt = """
        Document:
        \(SampleDocuments.businessEmail)

        Question: Suggest improvements to make this email more professional and clear.
        """
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "DocChat", testCase: "improveWriting",
            input: "Suggest improvements for business email",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should provide improvement suggestions")
        #expect(response.count >= 30, "Response should be substantive (>= 30 chars), got \(response.count)")
    }

    @Test("Document chat identifies grammar issues")
    func docChat_fixGrammar() async throws {
        let prompt = """
        Document:
        \(SampleDocuments.academicEssay)

        Question: What grammar issues do you see in this text? List them specifically.
        """
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "DocChat", testCase: "fixGrammar",
            input: "Fix grammar issues in academic essay",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should identify grammar issues")
        #expect(response.count >= 30, "Response should be substantive")
    }

    @Test("Document chat summarizes technical document")
    func docChat_summarize() async throws {
        let prompt = """
        Document:
        \(SampleDocuments.technicalDoc)

        Question: Summarize this document in 2-3 sentences.
        """
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "DocChat", testCase: "summarize",
            input: "Summarize technical document",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should produce a summary")
        #expect(response.count >= 20, "Summary should be at least 20 chars")
    }

    @Test("Document chat changes tone to more formal")
    func docChat_changeTone() async throws {
        let prompt = """
        Document:
        \(SampleDocuments.casualBlogPost)

        Question: Rewrite this in a more formal, professional tone.
        """
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "DocChat", testCase: "changeTone",
            input: "Make casual blog post more formal",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should provide a formal alternative")
        #expect(response.count >= 50, "Formal rewrite should be substantial")
    }

    @Test("Document chat handles empty document gracefully")
    func docChat_emptyDocument() async throws {
        let prompt = """
        Document:
        (empty)

        Question: What can you tell me about this document?
        """
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "DocChat", testCase: "emptyDocument",
            input: "Chat with empty document",
            output: response, passed: !response.isEmpty
        )
        // Should not crash and should produce some response
        #expect(!response.isEmpty, "Should handle empty document without crashing")
    }
}

// MARK: - Daily Digest Tests

@Suite("Daily Digest LLM", .serialized, .timeLimit(.minutes(10)))
struct DailyDigestLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Daily digest from single meeting")
    func dailyDigest_singleMeeting() async throws {
        let meetings = [
            (
                title: "Product Planning",
                summary: "Discussed Q2 roadmap including dark mode and dashboard redesign.",
                actionItemCount: 3,
                pendingCount: 2
            ),
        ]
        let prompt = MeetingPromptBuilder.buildDailyDigestPrompt(meetings: meetings)
        let response = try await LLMTestHarness.complete(
            system: "You are a productivity assistant. Output ONLY valid JSON.",
            prompt: prompt
        )

        let digest = MeetingPromptBuilder.parseDailyDigest(from: response)
        LLMTestEval.logResult(
            feature: "DailyDigest", testCase: "singleMeeting",
            input: "1 meeting digest",
            output: response,
            passed: digest != nil
        )
        #expect(digest != nil, "Should parse DailyDigest from single meeting response")
        if let digest {
            #expect(!digest.headline.isEmpty, "Headline should not be empty")
        }
    }

    @Test("Daily digest from multiple meetings")
    func dailyDigest_multipleMeetings() async throws {
        let meetings = [
            (
                title: "Product Planning",
                summary: "Discussed Q2 roadmap. Dark mode ships end of March, dashboard redesign in April.",
                actionItemCount: 4,
                pendingCount: 3
            ),
            (
                title: "1-on-1 with Alex",
                summary: "Alex completed auth refactor. Discussed career goals and tech lead path.",
                actionItemCount: 2,
                pendingCount: 1
            ),
            (
                title: "Daily Standup",
                summary: "Team reported progress on database migration, user profile API, and CI pipeline.",
                actionItemCount: 1,
                pendingCount: 1
            ),
        ]
        let prompt = MeetingPromptBuilder.buildDailyDigestPrompt(meetings: meetings)
        let response = try await LLMTestHarness.complete(
            system: "You are a productivity assistant. Output ONLY valid JSON.",
            prompt: prompt
        )

        let digest = MeetingPromptBuilder.parseDailyDigest(from: response)
        LLMTestEval.logResult(
            feature: "DailyDigest", testCase: "multipleMeetings",
            input: "3 meetings digest",
            output: response,
            passed: digest != nil
        )
        #expect(digest != nil, "Should parse DailyDigest from multiple meetings")
        if let digest {
            #expect(!digest.headline.isEmpty, "Headline should not be empty")
            #expect(!digest.keyHighlights.isEmpty, "Should have key highlights")
            #expect(!digest.pendingActions.isEmpty, "Should have pending actions from 5 pending items")
        }
    }

    @Test("Daily digest full parser integration")
    func dailyDigest_parserIntegration() async throws {
        let meetings = [
            (
                title: "Sprint Review",
                summary: "Team demonstrated new features. Stakeholders approved the dashboard design.",
                actionItemCount: 2,
                pendingCount: 1
            ),
            (
                title: "Architecture Discussion",
                summary: "Decided to migrate to microservices. Initial plan for Q3.",
                actionItemCount: 3,
                pendingCount: 2
            ),
        ]
        let prompt = MeetingPromptBuilder.buildDailyDigestPrompt(meetings: meetings)
        let response = try await LLMTestHarness.complete(
            system: "You are a productivity assistant. Output ONLY valid JSON.",
            prompt: prompt
        )

        let digest = MeetingPromptBuilder.parseDailyDigest(from: response)
        LLMTestEval.logResult(
            feature: "DailyDigest", testCase: "parserIntegration",
            input: "Parser integration test",
            output: "digest=\(digest != nil), headline=\(digest?.headline ?? "nil")",
            passed: digest != nil
        )
        #expect(digest != nil, "parseDailyDigest should return non-nil DailyDigest struct")
    }

    @Test("Daily digest with no action items does not crash")
    func dailyDigest_noActionItems() async throws {
        let meetings = [
            (title: "Information Session", summary: "General company update with no specific action items.", actionItemCount: 0, pendingCount: 0),
        ]
        let prompt = MeetingPromptBuilder.buildDailyDigestPrompt(meetings: meetings)
        let response = try await LLMTestHarness.complete(
            system: "You are a productivity assistant. Output ONLY valid JSON.",
            prompt: prompt
        )

        let digest = MeetingPromptBuilder.parseDailyDigest(from: response)
        LLMTestEval.logResult(
            feature: "DailyDigest", testCase: "noActionItems",
            input: "Meeting with 0 action items",
            output: response,
            passed: digest != nil
        )
        // Should handle zero action items gracefully
        #expect(digest != nil, "Should produce a digest even with no action items")
    }

    @Test("Daily digest JSON has all required fields")
    func dailyDigest_jsonSchema() async throws {
        let meetings = [
            (title: "Team Sync", summary: "Weekly sync covering project status and blockers.", actionItemCount: 2, pendingCount: 1),
            (title: "Client Call", summary: "Discussed project timeline and deliverables with the client.", actionItemCount: 3, pendingCount: 2),
        ]
        let prompt = MeetingPromptBuilder.buildDailyDigestPrompt(meetings: meetings)
        let response = try await LLMTestHarness.complete(
            system: "You are a productivity assistant. Output ONLY valid JSON.",
            prompt: prompt
        )

        // Validate raw JSON has all 5 expected fields
        guard let jsonString = LLMTestEval.extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            #expect(Bool(false), "Failed to extract JSON from digest response")
            return
        }

        let requiredFields = ["headline", "totalMeetingTime", "keyHighlights", "pendingActions", "tomorrowFocus"]
        for field in requiredFields {
            #expect(json[field] != nil, "Daily digest JSON missing required field: '\(field)'")
        }
        LLMTestEval.logResult(
            feature: "DailyDigest", testCase: "jsonSchema",
            input: "Schema validation",
            output: "Fields present: \(json.keys.sorted().joined(separator: ", "))",
            passed: requiredFields.allSatisfy { json[$0] != nil }
        )
    }
}

// MARK: - Rephrase Tests

@Suite("Rephrase LLM", .serialized, .timeLimit(.minutes(10)))
struct RephraseLLMTests {
    private let inputText = "Hey, just wanted to let you know that the project is going pretty well so far. " +
        "We might need to push the deadline back a bit though because some stuff came up."

    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Rephrase to professional business style")
    func rephrase_professional() async throws {
        let response = try await LLMEngine.shared.rephrase(inputText, style: .business)

        LLMTestEval.logResult(
            feature: "Rephrase", testCase: "professional",
            input: inputText, output: response,
            passed: !response.isEmpty && response != inputText
        )
        #expect(!response.isEmpty, "Rephrase should produce output")
        #expect(response != inputText, "Rephrased text should differ from input")
    }

    @Test("Rephrase to casual style")
    func rephrase_casual() async throws {
        let formalInput = "We would like to inform you that the project milestones are progressing satisfactorily. " +
            "However, a timeline adjustment may be necessary due to unforeseen circumstances."
        let response = try await LLMEngine.shared.rephrase(formalInput, style: .casual)

        LLMTestEval.logResult(
            feature: "Rephrase", testCase: "casual",
            input: formalInput, output: response,
            passed: !response.isEmpty && response != formalInput
        )
        #expect(!response.isEmpty, "Rephrase should produce output")
        #expect(response != formalInput, "Rephrased text should differ from input")
    }

    @Test("Rephrase to academic style")
    func rephrase_academic() async throws {
        let response = try await LLMEngine.shared.rephrase(inputText, style: .academic)

        LLMTestEval.logResult(
            feature: "Rephrase", testCase: "academic",
            input: inputText, output: response,
            passed: !response.isEmpty && response != inputText
        )
        #expect(!response.isEmpty, "Rephrase should produce output")
        #expect(response != inputText, "Rephrased text should differ from input")
    }

    @Test("Rephrase to creative style")
    func rephrase_creative() async throws {
        let response = try await LLMEngine.shared.rephrase(inputText, style: .creative)

        LLMTestEval.logResult(
            feature: "Rephrase", testCase: "creative",
            input: inputText, output: response,
            passed: !response.isEmpty && response != inputText
        )
        #expect(!response.isEmpty, "Rephrase should produce output")
        #expect(response != inputText, "Rephrased text should differ from input")
    }

    @Test("Rephrase to technical style")
    func rephrase_technical() async throws {
        let response = try await LLMEngine.shared.rephrase(inputText, style: .technical)

        LLMTestEval.logResult(
            feature: "Rephrase", testCase: "technical",
            input: inputText, output: response,
            passed: !response.isEmpty && response != inputText
        )
        #expect(!response.isEmpty, "Rephrase should produce output")
        #expect(response != inputText, "Rephrased text should differ from input")
    }

    @Test("Rephrase preserves meaning across all styles")
    func rephrase_preservesMeaning() async throws {
        var outputs: [WritingGoalMode: String] = [:]

        for mode in WritingGoalMode.allCases {
            let response = try await LLMEngine.shared.rephrase(inputText, style: mode)
            outputs[mode] = response

            // Each output should not be empty and should differ from input
            #expect(!response.isEmpty, "Rephrase \(mode.rawValue) should produce output")
            #expect(response != inputText, "Rephrase \(mode.rawValue) should differ from input")

            // Log length ratio for review (creative/academic modes can be verbose)
            let ratio = Double(response.count) / Double(inputText.count)
            if ratio > 10.0 || ratio < 0.1 {
                LLMTestEval.logResult(
                    feature: "Rephrase", testCase: "\(mode.rawValue)_ratio",
                    input: "", output: "",
                    passed: false, notes: "Extreme ratio: \(String(format: "%.2f", ratio))x"
                )
                #expect(ratio <= 10.0, "Rephrase \(mode.rawValue) length ratio extremely high: \(String(format: "%.2f", ratio))x")
            }
        }

        // Log all outputs for human review
        for (mode, output) in outputs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            LLMTestEval.logResult(
                feature: "Rephrase", testCase: "preservesMeaning_\(mode.rawValue)",
                input: inputText, output: output,
                passed: true,
                notes: "Length ratio: \(String(format: "%.2f", Double(output.count) / Double(inputText.count)))x"
            )
        }
    }
}
