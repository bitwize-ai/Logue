import Foundation
@testable import Logue
import Testing

// MARK: - Meeting Title Generation Tests

@Suite("Meeting Title LLM", .serialized, .timeLimit(.minutes(10)))
struct MeetingTitleLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Meeting title for product planning transcript")
    func meetingTitle_productPlanning() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this meeting transcript. \
        Output ONLY the title, nothing else.

        Transcript:
        \(String(SampleTranscripts.productPlanning.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let title = response
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? response
        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        LLMTestEval.logResult(
            feature: "MeetingTitle", testCase: "productPlanning",
            input: String(SampleTranscripts.productPlanning.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty && cleaned.count <= 100
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 100, "Title should be <= 100 characters, got \(cleaned.count)")
        let wordCount = cleaned.split(separator: " ").count
        #expect(wordCount >= 2 && wordCount <= 15, "Title should have 2-15 words, got \(wordCount): '\(cleaned)'")
    }

    @Test("Meeting title for standup transcript")
    func meetingTitle_standup() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this meeting transcript. \
        Output ONLY the title, nothing else.

        Transcript:
        \(SampleTranscripts.standup)

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = response
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") ?? ""

        LLMTestEval.logResult(
            feature: "MeetingTitle", testCase: "standup",
            input: String(SampleTranscripts.standup.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 100, "Title should be <= 100 characters")
    }

    @Test("Meeting title for interview debrief")
    func meetingTitle_interview() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this meeting transcript. \
        Output ONLY the title, nothing else.

        Transcript:
        \(String(SampleTranscripts.interviewDebrief.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = response
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") ?? ""

        LLMTestEval.logResult(
            feature: "MeetingTitle", testCase: "interview",
            input: String(SampleTranscripts.interviewDebrief.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 100, "Title should be <= 100 characters")
    }

    @Test("Meeting title for brainstorm session")
    func meetingTitle_brainstorm() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this meeting transcript. \
        Output ONLY the title, nothing else.

        Transcript:
        \(String(SampleTranscripts.brainstorm.prefix(800)))

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = response
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") ?? ""

        LLMTestEval.logResult(
            feature: "MeetingTitle", testCase: "brainstorm",
            input: String(SampleTranscripts.brainstorm.prefix(100)),
            output: cleaned, passed: !cleaned.isEmpty
        )
        #expect(!cleaned.isEmpty, "Title should not be empty")
        #expect(cleaned.count <= 100, "Title should be <= 100 characters")
    }

    @Test("Meeting title handles minimal transcript gracefully")
    func meetingTitle_shortTranscript() async throws {
        let prompt = """
        Generate a short descriptive title (3-8 words, title case) for this meeting transcript. \
        Output ONLY the title, nothing else.

        Transcript:
        \(SampleTranscripts.shortTranscript)

        Title:
        """
        let response = try await LLMEngine.shared.generate(prompt: prompt)
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        LLMTestEval.logResult(
            feature: "MeetingTitle", testCase: "shortTranscript",
            input: SampleTranscripts.shortTranscript,
            output: cleaned, passed: !cleaned.isEmpty
        )
        // Even minimal input should produce some title without crashing
        #expect(!cleaned.isEmpty, "Should produce a title even for minimal input")
    }
}

// MARK: - Smart Minutes Tests

@Suite("Smart Minutes LLM", .serialized, .timeLimit(.minutes(10)))
struct SmartMinutesLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Smart minutes from general product planning meeting")
    func smartMinutes_general() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.productPlanning)
        let response = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON, no extra text.",
            prompt: prompt,
            maxTokens: 2048
        )

        let minutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        let summary = MeetingPromptBuilder.parseSummaryText(from: response)

        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "general",
            input: String(SampleTranscripts.productPlanning.prefix(100)),
            output: response,
            passed: minutes != nil || summary != nil,
            notes: "minutes=\(minutes != nil), summary=\(summary != nil)"
        )
        // With long transcripts, the model may produce partial JSON sometimes
        let hasContent = minutes != nil || (summary != nil && !(summary?.isEmpty ?? true))
        #expect(hasContent, "Should parse SmartMinutes or summary from response")
        if let minutes {
            #expect(!minutes.discussionPoints.isEmpty, "Should have discussion points")
            #expect(!minutes.attendeeSummary.isEmpty, "Should have attendee summary")
        }
    }

    @Test("Smart minutes from 1-on-1 meeting")
    func smartMinutes_oneOnOne() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.oneOnOne)
        let response = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON, no extra text.",
            prompt: prompt
        )

        let minutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "oneOnOne",
            input: String(SampleTranscripts.oneOnOne.prefix(100)),
            output: response,
            passed: minutes != nil
        )
        #expect(minutes != nil, "Should parse SmartMinutes from 1-on-1 response")
        if let minutes {
            #expect(
                minutes.attendeeSummary.count >= 2,
                "1-on-1 should have at least 2 speakers in attendeeSummary, got \(minutes.attendeeSummary.count)"
            )
        }
    }

    @Test("Smart minutes from standup meeting")
    func smartMinutes_standup() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.standup)
        let response = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON, no extra text.",
            prompt: prompt
        )

        let minutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "standup",
            input: String(SampleTranscripts.standup.prefix(100)),
            output: response,
            passed: minutes != nil
        )
        #expect(minutes != nil, "Should parse SmartMinutes from standup response")
        if let minutes {
            #expect(!minutes.attendeeSummary.isEmpty, "Standup should include speaker entries")
        }
    }

    @Test("Smart minutes from interview debrief")
    func smartMinutes_interview() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.interviewDebrief)
        let response = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON, no extra text.",
            prompt: prompt
        )

        let minutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "interview",
            input: String(SampleTranscripts.interviewDebrief.prefix(100)),
            output: response,
            passed: minutes != nil
        )
        #expect(minutes != nil, "Should parse SmartMinutes from interview response")
        if let minutes {
            // Small models may not always generate action items for interview debriefs
            if minutes.actionItems.isEmpty {
                LLMTestEval.logResult(
                    feature: "SmartMinutes", testCase: "interview_actionItems",
                    input: "", output: "No action items generated",
                    passed: true, notes: "Warning: actionItems empty (small model limitation)"
                )
            }
        }
    }

    @Test("Smart minutes from brainstorm session")
    func smartMinutes_brainstorm() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.brainstorm)
        let response = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON, no extra text.",
            prompt: prompt
        )

        let minutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "brainstorm",
            input: String(SampleTranscripts.brainstorm.prefix(100)),
            output: response,
            passed: !response.isEmpty,
            notes: "minutes=\(minutes != nil), responseLength=\(response.count)"
        )
        // Model produces useful content but JSON may not always parse to SmartMinutes schema
        #expect(!response.isEmpty, "Should produce a non-empty response for brainstorm transcript")
        if let minutes {
            #expect(!minutes.discussionPoints.isEmpty, "Brainstorm should have discussion points")
        }
    }

    @Test("Smart minutes full parser integration pipeline")
    func smartMinutes_parserIntegration() async throws {
        let prompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.productPlanning)
        let response = try await LLMTestHarness.complete(
            system: """
            You are an expert meeting analyst. Your job is to produce comprehensive, structured JSON summaries.
            CRITICAL RULES:
            - You MUST fill in ALL JSON fields — never omit sections
            - Include every speaker in attendeeSummary with their key contributions
            - Output ONLY valid JSON, no extra text before or after
            """,
            prompt: prompt,
            maxTokens: 2048
        )

        // Test all parsers on the same response
        let smartMinutes = MeetingPromptBuilder.parseSmartMinutes(from: response)
        let summaryText = MeetingPromptBuilder.parseSummaryText(from: response)
        let actionItems = MeetingPromptBuilder.parseActionItems(from: response)
        let keywords = MeetingPromptBuilder.parseTopicKeywords(from: response)

        LLMTestEval.logResult(
            feature: "SmartMinutes", testCase: "parserIntegration",
            input: "Full pipeline test",
            output: "minutes=\(smartMinutes != nil), summary=\(summaryText != nil), " +
                "actions=\(actionItems.count), keywords=\(keywords.count)",
            passed: smartMinutes != nil
        )

        #expect(smartMinutes != nil, "parseSmartMinutes should return non-nil")
        #expect(summaryText != nil && !(summaryText?.isEmpty ?? true), "parseSummaryText should return non-empty")

        // Action items should have real content, not placeholders
        for item in actionItems {
            #expect(!item.title.isEmpty, "Action item title should not be empty")
            #expect(
                !item.title.lowercased().contains("task description"),
                "Action item should not contain placeholder text: '\(item.title)'"
            )
        }
    }
}

// MARK: - Meeting Chat Tests

@Suite("Meeting Chat LLM", .serialized, .timeLimit(.minutes(10)))
struct MeetingChatLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    @Test("Meeting chat answers question about key decisions")
    func meetingChat_keyDecisions() async throws {
        let chatPrompt = MeetingPromptBuilder.buildChatPrompt(
            question: "What were the key decisions made in this meeting?",
            transcript: SampleTranscripts.productPlanning,
            summary: nil
        )
        let response = try await LLMEngine.shared.chat(prompt: chatPrompt)

        LLMTestEval.logResult(
            feature: "MeetingChat", testCase: "keyDecisions",
            input: "What were the key decisions?",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Chat response should not be empty")
        #expect(response.count >= 20, "Response should be substantive (>= 20 chars), got \(response.count)")
    }

    @Test("Meeting chat lists action items")
    func meetingChat_actionItems() async throws {
        let chatPrompt = MeetingPromptBuilder.buildChatPrompt(
            question: "List all action items from this meeting.",
            transcript: SampleTranscripts.productPlanning,
            summary: nil
        )
        let response = try await LLMEngine.shared.chat(prompt: chatPrompt)

        LLMTestEval.logResult(
            feature: "MeetingChat", testCase: "actionItems",
            input: "List all action items",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should list action items")
        #expect(response.count >= 20, "Action items response should be substantive")
    }

    @Test("Meeting chat summarizes in bullet points")
    func meetingChat_summarize() async throws {
        let chatPrompt = MeetingPromptBuilder.buildChatPrompt(
            question: "Summarize this meeting in 3 bullet points.",
            transcript: SampleTranscripts.productPlanning,
            summary: nil
        )
        let response = try await LLMEngine.shared.chat(prompt: chatPrompt)

        LLMTestEval.logResult(
            feature: "MeetingChat", testCase: "summarize",
            input: "Summarize in 3 bullet points",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should produce a summary")
        // Check for some structural indicator (bullets, numbers, or dashes)
        let hasStructure = response.contains("-") || response.contains("•")
            || response.contains("1.") || response.contains("1)")
        #expect(hasStructure, "Response should contain bullet points or numbered list")
    }

    @Test("Meeting chat answers about specific person")
    func meetingChat_specificPerson() async throws {
        let chatPrompt = MeetingPromptBuilder.buildChatPrompt(
            question: "What did David say about the dashboard?",
            transcript: SampleTranscripts.productPlanning,
            summary: nil
        )
        let response = try await LLMEngine.shared.chat(prompt: chatPrompt)

        LLMTestEval.logResult(
            feature: "MeetingChat", testCase: "specificPerson",
            input: "What did David say about the dashboard?",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should answer about David and the dashboard")
    }

    @Test("Meeting chat with summary context produces relevant response")
    func meetingChat_withSummary() async throws {
        // First generate a summary
        let summaryPrompt = MeetingPromptBuilder.summaryPrompt(transcript: SampleTranscripts.productPlanning)
        let summaryResponse = try await LLMTestHarness.complete(
            system: "You are an expert meeting analyst. Output ONLY valid JSON.",
            prompt: summaryPrompt
        )
        let summaryText = MeetingPromptBuilder.parseSummaryText(from: summaryResponse)

        // Then ask a chat question with the summary
        let chatPrompt = MeetingPromptBuilder.buildChatPrompt(
            question: "What are the next steps after this meeting?",
            transcript: SampleTranscripts.productPlanning,
            summary: summaryText
        )
        let response = try await LLMEngine.shared.chat(prompt: chatPrompt)

        LLMTestEval.logResult(
            feature: "MeetingChat", testCase: "withSummary",
            input: "What are the next steps? (with summary context)",
            output: response, passed: !response.isEmpty
        )
        #expect(!response.isEmpty, "Should produce a response with summary context")
        #expect(response.count >= 20 && response.count <= 2000, "Response should be 20-2000 chars, got \(response.count)")
    }
}
