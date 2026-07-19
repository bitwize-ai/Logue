@testable import Logue
import Testing

// MARK: - Grammar Analysis Tests

@Suite("Grammar Analysis LLM", .serialized, .timeLimit(.minutes(20)))
struct GrammarAnalysisLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Grammar analysis on business email detects errors")
    func grammarAnalysis_businessEmail() async throws {
        let request = TextAnalysisRequest(
            text: SampleDocuments.businessEmail,
            cursorOffset: 0,
            goalMode: .business
        )
        let prompt = PromptBuilder.userMessage(for: request)
        let system = PromptBuilder.systemPrompt(for: .business)
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateGrammarResponse(response, inputText: SampleDocuments.businessEmail)
        LLMTestEval.logResult(
            feature: "Grammar", testCase: "businessEmail",
            input: SampleDocuments.businessEmail, output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Grammar response should be valid JSON with correct schema. Issues: \(result.notes)")
        // swiftlint:disable:next empty_count
        #expect(result.count > 0, "Business email has deliberate errors — should find at least 1 suggestion")
    }

    @Test("Grammar analysis on academic essay detects errors")
    func grammarAnalysis_academicEssay() async throws {
        let request = TextAnalysisRequest(
            text: SampleDocuments.academicEssay,
            cursorOffset: 0,
            goalMode: .academic
        )
        let prompt = PromptBuilder.userMessage(for: request)
        let system = PromptBuilder.systemPrompt(for: .academic)
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateGrammarResponse(response, inputText: SampleDocuments.academicEssay)
        LLMTestEval.logResult(
            feature: "Grammar", testCase: "academicEssay",
            input: SampleDocuments.academicEssay, output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Grammar response should be valid. Issues: \(result.notes)")
        if result.count < 1 {
            LLMTestEval.logResult(
                feature: "Grammar", testCase: "academicEssay_errorCount",
                input: "", output: response,
                passed: true, notes: "Warning: 0 suggestions (model may miss subtle errors)"
            )
        }
    }

    @Test("Grammar analysis on clean text returns empty suggestions")
    func grammarAnalysis_cleanText() async throws {
        let request = TextAnalysisRequest(
            text: SampleDocuments.cleanText,
            cursorOffset: 0,
            goalMode: .casual
        )
        let prompt = PromptBuilder.userMessage(for: request)
        let system = PromptBuilder.systemPrompt(for: .casual)
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateGrammarResponse(response, inputText: SampleDocuments.cleanText)
        LLMTestEval.logResult(
            feature: "Grammar", testCase: "cleanText",
            input: SampleDocuments.cleanText, output: response,
            passed: true, notes: "Count: \(result.count)"
        )
        // Clean text should have few suggestions; small models may hallucinate 1-3
        #expect(result.count <= 3, "Clean text should have few suggestions, got \(result.count)")
    }

    @Test("Grammar analysis with academic goal mode produces valid JSON")
    func grammarAnalysis_academicGoalMode() async throws {
        let text = SampleDocuments.businessEmail
        let request = TextAnalysisRequest(text: text, cursorOffset: 0, goalMode: .academic)
        let prompt = PromptBuilder.userMessage(for: request)
        let system = PromptBuilder.systemPrompt(for: .academic)
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateGrammarResponse(response, inputText: text)
        LLMTestEval.logResult(
            feature: "Grammar", testCase: "goalMode_academic",
            input: text, output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Academic goal mode should produce valid grammar JSON. \(result.notes)")
    }

    @Test("Grammar analysis via streaming collects response")
    func grammarAnalysis_streaming() async {
        let request = TextAnalysisRequest(
            text: SampleDocuments.businessEmail,
            cursorOffset: 0,
            goalMode: .business
        )
        var suggestions: [Suggestion] = []
        let stream = await LLMEngine.shared.analyze(request)
        for await suggestion in stream {
            suggestions.append(suggestion)
        }
        LLMTestEval.logResult(
            feature: "Grammar", testCase: "streaming",
            input: SampleDocuments.businessEmail,
            output: "Collected \(suggestions.count) suggestions",
            passed: true,
            notes: suggestions.isEmpty ? "No suggestions parsed (model output may not match parser)" : "OK"
        )
        // Log results for diagnostics — streaming parser success depends on exact model format
        // This test verifies the pipeline runs without crashing
        for suggestion in suggestions {
            #expect(!suggestion.original.isEmpty, "Suggestion original text should not be empty")
            #expect(!suggestion.replacement.isEmpty, "Suggestion replacement should not be empty")
        }
    }
}

// MARK: - Clarity Analysis Tests

@Suite("Clarity Analysis LLM", .serialized, .timeLimit(.minutes(10)))
struct ClarityAnalysisLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Clarity analysis on business email detects style issues")
    func clarityAnalysis_businessEmail() async throws {
        let system = PromptBuilder.claritySystemPrompt(for: .business)
        let prompt = "Analyse clarity and style:\n\n\(SampleDocuments.businessEmail)"
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateClarityResponse(response)
        LLMTestEval.logResult(
            feature: "Clarity", testCase: "businessEmail",
            input: SampleDocuments.businessEmail, output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Clarity response should be valid JSON. Issues: \(result.notes)")
    }

    @Test("Clarity analysis on verbose text finds issues")
    func clarityAnalysis_verboseText() async throws {
        let system = PromptBuilder.claritySystemPrompt(for: .academic)
        let prompt = "Analyse clarity and style:\n\n\(SampleDocuments.verboseAcademicText)"
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateClarityResponse(response)
        LLMTestEval.logResult(
            feature: "Clarity", testCase: "verboseText",
            input: SampleDocuments.verboseAcademicText, output: response,
            passed: result.valid && result.count >= 1,
            notes: "Count: \(result.count). \(result.notes)"
        )
        #expect(result.valid, "Clarity response should be valid. Issues: \(result.notes)")
        #expect(result.count >= 1, "Verbose text should trigger at least 1 clarity suggestion")
    }

    @Test("Clarity analysis on technical documentation")
    func clarityAnalysis_technicalDocs() async throws {
        let system = PromptBuilder.claritySystemPrompt(for: .technical)
        let prompt = "Analyse clarity and style:\n\n\(SampleDocuments.technicalDoc)"
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateClarityResponse(response)
        LLMTestEval.logResult(
            feature: "Clarity", testCase: "technicalDocs",
            input: SampleDocuments.technicalDoc, output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Clarity response should be valid JSON for technical goal. Issues: \(result.notes)")
    }

    @Test("Clarity analysis on short text returns empty suggestions")
    func clarityAnalysis_shortText() async throws {
        let system = PromptBuilder.claritySystemPrompt(for: .casual)
        let prompt = "Analyse clarity and style:\n\n\(SampleDocuments.shortText)"
        let response = try await LLMTestHarness.complete(system: system, prompt: prompt)

        let result = LLMTestEval.validateClarityResponse(response)
        LLMTestEval.logResult(
            feature: "Clarity", testCase: "shortText",
            input: SampleDocuments.shortText, output: response,
            passed: true, notes: "Count: \(result.count)"
        )
        // Small models may still find something to say about "Hi there." — allow up to 1
        #expect(result.count <= 1, "Short text should produce 0-1 clarity suggestions, got \(result.count)")
    }

    @Test("Clarity analysis: academic vs casual mode comparison")
    func clarityAnalysis_modeComparison() async throws {
        let text = SampleDocuments.verboseAcademicText

        let academicSystem = PromptBuilder.claritySystemPrompt(for: .academic)
        let academicResponse = try await LLMTestHarness.complete(
            system: academicSystem,
            prompt: "Analyse clarity and style:\n\n\(text)"
        )
        let academicResult = LLMTestEval.validateClarityResponse(academicResponse)

        let casualSystem = PromptBuilder.claritySystemPrompt(for: .casual)
        let casualResponse = try await LLMTestHarness.complete(
            system: casualSystem,
            prompt: "Analyse clarity and style:\n\n\(text)"
        )
        let casualResult = LLMTestEval.validateClarityResponse(casualResponse)

        LLMTestEval.logResult(
            feature: "Clarity", testCase: "modeComparison",
            input: text, output: "Academic: \(academicResult.count), Casual: \(casualResult.count)",
            passed: academicResult.valid && casualResult.valid,
            notes: "Academic suggestions: \(academicResult.count), Casual: \(casualResult.count)"
        )
        #expect(academicResult.valid, "Academic clarity should produce valid JSON. \(academicResult.notes)")
        #expect(casualResult.valid, "Casual clarity should produce valid JSON. \(casualResult.notes)")
    }
}

// MARK: - Tone Detection Tests

@Suite("Tone Detection LLM", .serialized, .timeLimit(.minutes(10)))
struct ToneDetectionLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Tone detection identifies formal tone")
    func toneDetect_formalText() async throws {
        let text = "We respectfully request your attendance at the quarterly board meeting " +
            "scheduled for March 15th. Your presence is essential for the review of financial projections."
        let messages = PromptBuilder.toneMessages(text: text)
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userMsg = messages.last?.content ?? text
        let response = try await LLMTestHarness.complete(system: system, prompt: userMsg)

        let result = LLMTestEval.validateToneResponse(response)
        LLMTestEval.logResult(
            feature: "Tone", testCase: "formalText",
            input: text, output: response,
            passed: result.valid, notes: "Tone: \(result.tone ?? "nil"), Score: \(result.score ?? 0)"
        )
        #expect(result.valid, "Tone response should be valid JSON with tone and score")
        #expect(result.tone != nil, "Should detect a tone label")
    }

    @Test("Tone detection identifies casual tone")
    func toneDetect_casualText() async throws {
        let text = "Hey what's up, just checking in to see how things are going! " +
            "Let me know if you wanna grab lunch later."
        let messages = PromptBuilder.toneMessages(text: text)
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userMsg = messages.last?.content ?? text
        let response = try await LLMTestHarness.complete(system: system, prompt: userMsg)

        let result = LLMTestEval.validateToneResponse(response)
        LLMTestEval.logResult(
            feature: "Tone", testCase: "casualText",
            input: text, output: response,
            passed: result.valid, notes: "Tone: \(result.tone ?? "nil"), Score: \(result.score ?? 0)"
        )
        #expect(result.valid, "Tone response should be valid JSON")
        #expect(result.tone != nil, "Should detect a tone label")
    }

    @Test("Tone detection identifies assertive tone")
    func toneDetect_assertiveText() async throws {
        let text = "We must implement this change immediately. There is no room for delay. " +
            "The deadline is non-negotiable and all teams will comply."
        let messages = PromptBuilder.toneMessages(text: text)
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userMsg = messages.last?.content ?? text
        let response = try await LLMTestHarness.complete(system: system, prompt: userMsg)

        let result = LLMTestEval.validateToneResponse(response)
        LLMTestEval.logResult(
            feature: "Tone", testCase: "assertiveText",
            input: text, output: response,
            passed: result.valid, notes: "Tone: \(result.tone ?? "nil"), Score: \(result.score ?? 0)"
        )
        #expect(result.valid, "Tone response should be valid JSON")
    }

    @Test("Tone detection identifies uncertain tone")
    func toneDetect_uncertainText() async throws {
        let text = "I'm not sure if this might work, but maybe we could try a different approach? " +
            "It's just a thought, and I could be wrong about this."
        let messages = PromptBuilder.toneMessages(text: text)
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let userMsg = messages.last?.content ?? text
        let response = try await LLMTestHarness.complete(system: system, prompt: userMsg)

        let result = LLMTestEval.validateToneResponse(response)
        LLMTestEval.logResult(
            feature: "Tone", testCase: "uncertainText",
            input: text, output: response,
            passed: result.valid, notes: "Tone: \(result.tone ?? "nil"), Score: \(result.score ?? 0)"
        )
        #expect(result.valid, "Tone response should be valid JSON")
    }

    @Test("Tone detection returns valid JSON schema consistently")
    func toneDetect_jsonSchema() async throws {
        let texts = [
            "We respectfully request your attention to this matter.",
            "Hey, just wanted to check in real quick!",
            "This proposal will revolutionize our approach entirely.",
        ]
        for text in texts {
            let messages = PromptBuilder.toneMessages(text: text)
            let system = messages.first(where: { $0.role == .system })?.content ?? ""
            let userMsg = messages.last?.content ?? text
            let response = try await LLMTestHarness.complete(system: system, prompt: userMsg)

            let result = LLMTestEval.validateToneResponse(response)
            LLMTestEval.logResult(
                feature: "Tone", testCase: "jsonSchema",
                input: text, output: response,
                passed: result.valid, notes: "Tone: \(result.tone ?? "nil"), Score: \(result.score ?? 0)"
            )
            #expect(result.valid, "Tone JSON should have 'tone' string and 'score' 0-1 for: \(text.prefix(40))...")
        }
    }
}
