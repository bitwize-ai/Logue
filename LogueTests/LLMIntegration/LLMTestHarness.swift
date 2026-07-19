import Foundation
@testable import Logue

// MARK: - Model Loading

/// Shared model loading for all LLM integration tests.
/// Call `ensureModelLoaded()` before any test that needs inference.
enum LLMTestHarness {
    private static let modelRepoID = "mlx-community/JOSIE-1.1-4B-Instruct-4bit"

    /// Approximate on-disk size (GB) of the 4-bit test model. Used only for the
    /// download-progress estimate; correctness does not depend on it.
    private static let modelSizeGB = 2.5

    enum HarnessError: Error, CustomStringConvertible {
        case modelLoadFailed(String)

        var description: String {
            switch self {
            case let .modelLoadFailed(reason): "Test model failed to load: \(reason)"
            }
        }
    }

    static func ensureModelLoaded() async throws {
        guard await !LLMEngine.shared.isModelLoaded else { return }

        // Drive the same on-device MLX download + activate path the app uses, so the
        // integration suites exercise real local inference. No external LLM client is
        // involved — the model is downloaded from Hugging Face and run via mlx-swift-lm.
        let record = ModelConfiguration.customMLX(repoID: modelRepoID, sizeGB: modelSizeGB)
        await ModelManager.shared.downloadAndActivateInternal(record, autoActivate: true)

        guard await LLMEngine.shared.isModelLoaded else {
            let reason = await ModelManager.shared.activationError ?? "download or activation failed"
            throw HarnessError.modelLoadFailed(reason)
        }
    }

    /// Complete with test-friendly defaults: lower temperature for deterministic JSON,
    /// higher maxTokens to prevent truncation.
    static func complete(
        system: String,
        prompt: String,
        temperature: Double = 0.3,
        maxTokens: Int = 1024
    ) async throws -> String {
        try await LLMEngine.shared.complete(
            system: system,
            prompt: prompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

// MARK: - Sample Documents

enum SampleDocuments {
    static let businessEmail = """
    Dear Mr. Thompson,

    I am writing to inform you about the quartely financial results for Q3. Their was a significant \
    increase in revenue compared to last year, however we noticed some discrepencies in the accounting \
    reports that need to be addressed. I dont think we should ignore these issues as they could affect \
    our audit results.

    Please find the attached spreadsheet with furthur details. We should schedule a meeting to discuss \
    these findings and develop an action plan before the board meeting next week.

    Looking forward to your response.

    Best regards,
    Sarah Chen
    """

    static let academicEssay = """
    The impact of social media on adolescent mental health has became a subject of intense scholarly \
    debate over the past decade. Several studys have attempted to establish a causal link between \
    screen time and depressive symptoms, though the evidence remain mixed. While some researchers \
    argue that excessive social media use correlate with increased anxiety and lower self-esteem, \
    others point to the platform's potential for fostering community and social support.

    This paper examines the methodological limitations of existing research and proposes a \
    longitudinal framework that accounts for confounding variables such as socioeconomic status, \
    pre-existing mental health conditions, and family dynamics.
    """

    static let casualBlogPost = """
    So I finally tried that new coffee shop downtown and honestly its way more bigger then I expected. \
    The atmosphere was super chill and the baristas were really friendly. I ordered a lavender oat milk \
    latte which sounds weird but trust me its amazing.

    The prices are pretty reasonable to especially for the portion sizes. I sat there for like 3 hours \
    working on my laptop and nobody seemed to mind. If your looking for a good work-from-cafe spot \
    I definitely recommend checking it out.
    """

    static let technicalDoc = """
    The authentication module implements OAuth 2.0 with PKCE extention for secure token exchange. \
    When a user initates the login flow, the client generates a code verifier and it's corresponding \
    challenge. The authorization server validates the challenge before issuing access tokens.

    Configuration: Set the `AUTH_REDIRECT_URI` environment variable to match your registered callback URL. \
    The token refresh strategie uses exponential backoff with a maximum of 5 retry attempts. \
    Ensure that the client secret is stored securely and never exposed in client-side code.
    """

    static let creativeWriting = """
    The lighthouse stood alone on the rocky promontory, it's beam cutting through the fog like a \
    golden knife. Every night for thirty years, old Thomas had climbed the spiral staircase to tend \
    the light, hisself growing more weathered with each passing season.

    Tonights was different though. The storm that had been brewing all week had finally arrived, \
    and the waves crashed against the rocks with a fury he hadn't seen in decades. He wondered \
    weather the old structure could withstand another night like this one.
    """

    static let cleanText = "The quick brown fox jumps over the lazy dog."

    static let shortText = "Hi there."

    static let verboseAcademicText = """
    It is important to note that in the current context of the situation at hand, the utilization of \
    passive voice constructions is being employed by the author in a manner that could potentially be \
    considered to be somewhat excessive in nature. The implementation of the aforementioned \
    methodological approach was carried out by the research team in a way that was deemed to be \
    satisfactory by the relevant stakeholders who were involved in the review process.
    """

    /// Document with deliberate PII across multiple categories for privacy scanning tests.
    static let piiLadenText = """
    CONFIDENTIAL — New Hire Onboarding Record

    Employee: John Michael Smith
    Date of Birth: March 15, 1988
    Gender: Male

    Contact Information:
    Email: john.smith@example.com
    Phone: (555) 867-5309
    Address: 742 Evergreen Terrace, Springfield, IL 62704

    Government IDs:
    SSN: 123-45-6789
    Driver's License: D400-7891-2345

    Compensation:
    Starting Salary: $95,000/year
    Bank Account (Direct Deposit): Chase, Account #4829103756

    Employment Details:
    Employee ID: EMP-2024-4521
    Department: Engineering
    Manager: Lisa Park

    Health Benefits:
    Insurance Member ID: INS-887654
    Primary Care Physician: Dr. Rachel Green
    Current Medications: Metformin 500mg

    IT Setup:
    VPN IP Address: 192.168.1.42
    API Key: sk-live-abc123def456ghi789
    Laptop Serial: C02ZN1YQLVDM
    """

    /// Document with a mix of verifiable, uncertain, and misleading factual claims.
    static let factualClaimsText = """
    The Earth orbits the Sun at an average distance of approximately 93 million miles. This \
    fundamental astronomical fact was established through centuries of observation and calculation.

    Python was created by Guido van Rossum and first released in 1991. It has since become one of \
    the most popular programming languages in the world, used in web development, data science, \
    and artificial intelligence.

    According to a recent survey, 87% of remote workers report higher productivity when working \
    from home compared to the office. This statistic has been widely cited in debates about \
    return-to-office policies.

    The Great Wall of China is visible from space with the naked eye. This impressive feat of \
    ancient engineering stretches over 13,000 miles across northern China.

    Albert Einstein failed math in school, which shows that academic performance is not always \
    a predictor of future success. He went on to develop the theory of relativity.

    Water boils at 100 degrees Celsius at standard atmospheric pressure at sea level. This \
    fundamental property of water is used as a reference point in the Celsius temperature scale.
    """
}

// MARK: - Sample Meeting Transcripts

enum SampleTranscripts {
    static let productPlanning = """
    [0:00] Sarah: Good morning everyone, let's get started with the product planning meeting. \
    We have a lot to cover today regarding the Q2 roadmap.
    [0:15] James: Thanks Sarah. I've been analyzing the user feedback from the beta release. \
    The top three feature requests are dark mode, offline support, and better search.
    [0:45] Maria: From the design side, dark mode is about 80% complete. We can ship it by end \
    of March if engineering can allocate two developers.
    [1:10] David: I can assign Mike and Chen to the dark mode implementation. They should be \
    able to finish the remaining UI components in two weeks.
    [1:30] Sarah: Great. What about the dashboard redesign? That was flagged as high priority \
    by the enterprise clients.
    [1:45] James: The analytics show that 40% of enterprise users aren't using the dashboard at \
    all because the current layout is confusing.
    [2:10] Maria: I've prepared three mockup options. Option B tested best in our user research \
    sessions with an 85% approval rate.
    [2:30] David: Let's go with Option B then. I'll create the Jira tickets for the frontend \
    team. We should target a mid-April release.
    [2:50] Sarah: Agreed. So our decisions today are: dark mode ships end of March, dashboard \
    redesign Option B targets mid-April. David, can you also look into the API performance \
    issues that were reported?
    [3:15] David: Yes, I'll investigate the slow response times on the search endpoint. Initial \
    profiling suggests it's a database indexing issue.
    [3:30] James: One more thing — we need to decide on the pricing for the new product tier. \
    Marketing wants to launch it alongside the dashboard update.
    [3:50] Sarah: Let's schedule a separate meeting for pricing with the finance team. Maria, \
    can you prepare the feature comparison chart by Friday?
    [4:05] Maria: Sure, I'll have it ready by Thursday actually.
    [4:15] Sarah: Perfect. To summarize: dark mode by end of March, dashboard Option B by \
    mid-April, David investigating API performance, and Maria preparing the feature chart by \
    Thursday. Next meeting is Wednesday same time.
    """

    static let oneOnOne = """
    [0:00] Lisa: Hi Alex, thanks for meeting. How was your week?
    [0:10] Alex: It was productive actually. I finished the authentication refactor and started \
    on the notification system.
    [0:25] Lisa: That's great progress. The auth refactor was a big piece of work. Any blockers?
    [0:35] Alex: The main challenge is the notification service integration. The third-party API \
    documentation is outdated, and I've been spending a lot of time debugging.
    [0:55] Lisa: I can reach out to their developer relations team for updated docs. Would that help?
    [1:05] Alex: That would be amazing, thanks. Also, I wanted to talk about my career goals. \
    I'm interested in moving toward a tech lead role.
    [1:20] Lisa: I think you're on the right track. You've been doing great work technically. \
    The areas I'd suggest focusing on are code review mentorship and architectural documentation.
    [1:40] Alex: Makes sense. Could I lead the next sprint planning session as practice?
    [1:50] Lisa: Absolutely. The next one is in two weeks. I'll set you up as the facilitator. \
    Let's also schedule a 360 feedback session with the team.
    [2:05] Alex: Sounds good. One more thing — I'd like to attend the Swift conference in June. \
    Is there budget for that?
    [2:15] Lisa: Let me check with the department budget. I'll have an answer by next Friday. \
    Great chat today, let's check in again next week.
    """

    static let standup = """
    [0:00] Mike: Morning team. Let's keep it quick. I'll start — yesterday I finished the \
    database migration script. Today I'm working on the data validation layer. No blockers.
    [0:15] Priya: Yesterday I completed the user profile API endpoints. Today I'm starting \
    the integration tests. One blocker — I need access to the staging environment credentials.
    [0:30] Tom: I can get you those credentials after standup, Priya. Yesterday I fixed the \
    memory leak in the WebSocket handler. Today I'm adding connection retry logic. No blockers.
    [0:45] Chen: Yesterday I reviewed three pull requests and paired with the QA team on test \
    automation. Today I'll finish the CI pipeline configuration. No blockers from my side.
    """

    static let interviewDebrief = """
    [0:00] Rachel: Let's debrief on the senior engineer interview with candidate John Park. \
    Mark, you led the technical round — how did it go?
    [0:15] Mark: John demonstrated strong system design skills. His approach to the distributed \
    cache problem was well-thought-out. He considered consistency trade-offs and proposed a \
    write-through strategy with TTL-based invalidation.
    [0:40] Anita: In the behavioral round, he showed good leadership examples. He described \
    leading a migration from monolith to microservices at his current company. My concern is \
    his communication style — he tends to go very deep into technical details without first \
    giving the high-level overview.
    [1:05] Rachel: That's a fair point. How about his coding skills, Mark?
    [1:15] Mark: The coding exercise went well. He solved the tree traversal problem in O(n) \
    time and wrote clean, well-structured code. He also caught an edge case I hadn't considered.
    [1:35] Anita: His questions about our team were thoughtful — he asked about our code review \
    process and how we handle technical debt.
    [1:50] Rachel: Overall recommendation? I'm leaning toward a hire with the caveat about \
    communication coaching.
    [2:00] Mark: I'd say strong hire. The technical skills are exactly what we need.
    [2:10] Anita: I agree — hire with a 30-60-90 day plan that includes presentation skills.
    [2:20] Rachel: Great, I'll submit the feedback. Action items: Mark writes the technical \
    assessment, Anita documents the behavioral evaluation, and I'll coordinate with HR on the \
    offer package. Let's aim to have everything submitted by Wednesday.
    """

    static let brainstorm = """
    [0:00] Kim: Welcome to the brainstorm session on improving our onboarding experience. \
    Let's throw out ideas freely — no bad ideas at this stage.
    [0:15] Leo: What if we add an interactive tutorial that walks new users through the main \
    features? Like a step-by-step overlay.
    [0:30] Sam: Building on that — we could gamify it. Give users badges or points for \
    completing onboarding steps. Maybe a progress bar that shows completion percentage.
    [0:50] Nina: I like the gamification angle. We could also add a personalization quiz at \
    the start — ask users what they want to accomplish and customize the onboarding flow.
    [1:10] Kim: Great ideas. What about the documentation? Our current help docs are pretty \
    dense and technical.
    [1:20] Leo: We could create short video tutorials — 30 seconds each, covering one feature \
    at a time. Users can watch them inline or skip.
    [1:35] Sam: AI-powered help could work too. An in-app assistant that answers questions \
    contextually based on what screen the user is on.
    [1:55] Nina: That ties in nicely with our AI roadmap. For the quick wins, I think the \
    interactive tutorial and personalization quiz are the most impactful.
    [2:10] Kim: I agree. Let's prioritize: interactive tutorial as the main effort, \
    personalization quiz as a follow-up. Leo, can you draft wireframes for the tutorial flow?
    [2:25] Leo: Sure, I'll have initial wireframes by next Monday.
    [2:35] Sam: I'll research gamification frameworks we could integrate.
    [2:45] Nina: And I'll put together user personas for the personalization quiz options.
    [2:55] Kim: Perfect. Let's reconvene Thursday to review progress. Great session everyone!
    """

    static let shortTranscript = "Hello everyone, let's begin."
}

// MARK: - Evaluation Helpers

enum LLMTestEval {
    /// Strip markdown code fences (```json ... ```) from LLM output.
    static func stripMarkdownFences(from text: String) -> String {
        var cleaned = text
        // Remove ```json or ``` at the start
        if let range = cleaned.range(of: #"```(?:json)?\s*\n?"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove trailing ```
        if let range = cleaned.range(of: #"\n?```\s*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the outermost JSON object from LLM response, stripping preamble and markdown fences.
    /// If the JSON is truncated (model hit maxTokens), attempts to repair by closing open brackets.
    static func extractJSON(from response: String) -> String? {
        let cleaned = stripMarkdownFences(from: response)
        guard let jsonStart = cleaned.firstIndex(of: "{") else { return nil }

        var depth = 0
        var jsonEnd = jsonStart
        var inString = false
        var prevChar: Character = " "

        for index in cleaned[jsonStart...].indices {
            let char = cleaned[index]
            if char == "\"", prevChar != "\\" {
                inString.toggle()
            }
            if !inString {
                if char == "{" { depth += 1 }
                if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        jsonEnd = index
                        break
                    }
                }
            }
            prevChar = char
        }

        if depth == 0 {
            return String(cleaned[jsonStart ... jsonEnd])
        }

        // JSON was truncated — try to repair by finding last complete item and closing brackets
        return repairTruncatedJSON(String(cleaned[jsonStart...]))
    }

    /// Attempts to repair truncated JSON by trimming to the last complete value
    /// and closing any open arrays/objects.
    private static func repairTruncatedJSON(_ json: String) -> String? {
        // Find the last complete JSON element boundary
        // Look for the last "}" that could end a complete array item
        var candidate = json

        // Trim trailing partial content: find last complete object in an array
        // Strategy: keep removing chars from the end until we find a parseable structure
        // after appending the necessary closing brackets
        while !candidate.isEmpty {
            // Count open/close brackets
            var objDepth = 0
            var arrDepth = 0
            var inStr = false
            var prev: Character = " "

            for char in candidate {
                if char == "\"", prev != "\\" { inStr.toggle() }
                if !inStr {
                    if char == "{" { objDepth += 1 }
                    if char == "}" { objDepth -= 1 }
                    if char == "[" { arrDepth += 1 }
                    if char == "]" { arrDepth -= 1 }
                }
                prev = char
            }

            // If in string, try trimming to before the opening quote
            if inStr {
                if let lastQuote = candidate.lastIndex(of: "\"") {
                    candidate = String(candidate[..<lastQuote])
                    continue
                }
            }

            // Try closing the brackets
            var repaired = candidate
            // Remove trailing comma if present
            let trimmed = repaired.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(",") {
                repaired = String(trimmed.dropLast())
            }
            for _ in 0 ..< arrDepth {
                repaired += "]"
            }
            for _ in 0 ..< objDepth {
                repaired += "}"
            }

            if let data = repaired.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil
            {
                return repaired
            }

            // Trim to the last "}" and try again
            if let lastBrace = candidate.lastIndex(of: "}") {
                candidate = String(candidate[...lastBrace])
            } else {
                break
            }
        }

        return nil
    }

    /// Log a structured test result for human review.
    static func logResult(
        feature: String,
        testCase: String,
        input: String,
        output: String,
        passed: Bool,
        notes: String = ""
    ) {
        let status = passed ? "PASS" : "FAIL"
        let truncatedInput = String(input.prefix(100))
        let truncatedOutput = String(output.prefix(300))
        print("""
        [\(status)] \(feature) / \(testCase)
          Input:  \(truncatedInput)...
          Output: \(truncatedOutput)
          \(notes.isEmpty ? "" : "Notes:  \(notes)")
        """)
    }

    /// Lenient suggestion item that handles missing confidence field.
    private struct LenientSuggestionItem: Decodable {
        let type: String
        let original: String
        let replacement: String
        let explanation: String
        let confidence: Double?
    }

    private struct LenientSuggestionResponse: Decodable {
        let suggestions: [LenientSuggestionItem]
    }

    /// Validate a grammar/spelling suggestion response from the LLM.
    /// Evaluates only the first `maxItems` suggestions (small models may repeat in loops).
    static func validateGrammarResponse(
        _ response: String,
        inputText: String,
        maxItems: Int = 5
    ) -> (valid: Bool, count: Int, notes: String) {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LenientSuggestionResponse.self, from: data)
        else {
            return (false, 0, "Failed to parse JSON from response. Raw prefix: \(String(response.prefix(200)))")
        }

        let validTypes: Set = ["grammar", "spelling", "punctuation"]
        var issues: [String] = []
        var warnings: [String] = []
        let totalCount = decoded.suggestions.count

        if totalCount > maxItems {
            warnings.append("Model returned \(totalCount) suggestions (repetition loop); evaluating first \(maxItems)")
        }

        // Evaluate only the first maxItems to handle repetition loops
        let itemsToCheck = Array(decoded.suggestions.prefix(maxItems))
        for (idx, item) in itemsToCheck.enumerated() {
            if !validTypes.contains(item.type) {
                issues.append("Item \(idx): invalid type '\(item.type)'")
            }
            let conf = item.confidence ?? 0.9 // Default confidence if model omits it
            if conf < 0.5 {
                issues.append("Item \(idx): confidence \(conf) < 0.5")
            } else if conf < 0.75 {
                warnings.append("Item \(idx): confidence \(conf) < 0.75 (soft)")
            }
            if item.confidence == nil {
                warnings.append("Item \(idx): confidence field missing")
            }
            if !inputText.contains(item.original) {
                warnings.append("Item \(idx): original '\(String(item.original.prefix(40)))' not verbatim in input")
            }
            if item.replacement.isEmpty {
                issues.append("Item \(idx): empty replacement")
            }
        }

        let allNotes = (issues + warnings).joined(separator: "; ")
        return (issues.isEmpty, totalCount, allNotes)
    }

    /// Validate a clarity/style suggestion response from the LLM.
    static func validateClarityResponse(_ response: String) -> (valid: Bool, count: Int, notes: String) {
        // Try lenient decoding first (handles missing confidence field)
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8)
        else {
            return (false, 0, "Failed to parse JSON from response. Raw prefix: \(String(response.prefix(200)))")
        }

        // Try lenient decoding first, fall back to standard
        let items: [LenientSuggestionItem]
        if let lenient = try? JSONDecoder().decode(LenientSuggestionResponse.self, from: data) {
            items = lenient.suggestions
        } else if let standard = try? JSONDecoder().decode(SuggestionResponse.self, from: data) {
            items = standard.suggestions.map {
                LenientSuggestionItem(
                    type: $0.type,
                    original: $0.original,
                    replacement: $0.replacement,
                    explanation: $0.explanation,
                    confidence: $0.confidence
                )
            }
        } else {
            return (false, 0, "Failed to parse JSON from response. Raw prefix: \(String(response.prefix(200)))")
        }

        let validTypes: Set = ["clarity", "conciseness", "style", "grammar", "spelling", "punctuation"]
        var issues: [String] = []
        let maxItems = 5

        // Small models may enter repetition loops — evaluate only first N items
        if items.count > maxItems {
            logResult(
                feature: "Clarity", testCase: "validation",
                input: "", output: "Model returned \(items.count) suggestions (repetition loop); evaluating first \(maxItems)",
                passed: true, notes: "Warning: over-generation"
            )
        }

        for (idx, item) in items.prefix(maxItems).enumerated() {
            if !validTypes.contains(item.type) {
                issues.append("Item \(idx): invalid type '\(item.type)'")
            }
            let confidence = item.confidence ?? 0.9
            if confidence < 0.5 {
                issues.append("Item \(idx): confidence \(confidence) < 0.5")
            }
        }

        return (issues.isEmpty, items.count, issues.joined(separator: "; "))
    }

    /// Validate a tone detection response from the LLM.
    static func validateToneResponse(_ response: String) -> (tone: String?, score: Double?, valid: Bool) {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tone = json["tone"] as? String,
              let score = json["score"] as? Double
        else {
            return (nil, nil, false)
        }
        let validTones: Set = [
            "confident", "uncertain", "formal", "informal",
            "friendly", "assertive", "passive", "neutral",
        ]
        let toneValid = validTones.contains(tone.lowercased())
        let scoreValid = score >= 0 && score <= 1
        return (tone, score, toneValid && scoreValid)
    }

    // MARK: - JSON Array Extraction

    /// Extract the outermost JSON array from LLM response, stripping preamble and markdown fences.
    static func extractJSONArray(from response: String) -> String? {
        let cleaned = stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "[") else { return nil }

        var depth = 0
        var arrEnd = arrStart
        var inString = false
        var prevChar: Character = " "

        for index in cleaned[arrStart...].indices {
            let char = cleaned[index]
            if char == "\"", prevChar != "\\" {
                inString.toggle()
            }
            if !inString {
                if char == "[" { depth += 1 }
                if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        arrEnd = index
                        break
                    }
                }
            }
            prevChar = char
        }

        if depth == 0 {
            return String(cleaned[arrStart ... arrEnd])
        }

        // Truncated — try repair
        return repairTruncatedJSON(String(cleaned[arrStart...]))
    }

    // MARK: - Grade Validation

    /// Validate a rubric grading response (Review Panel — Score tab).
    static func validateGradeResponse(
        _ response: String
    ) -> (valid: Bool, gradeCount: Int, averageScore: Int?, notes: String) {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (false, 0, nil, "Failed to extract JSON object. Raw prefix: \(String(response.prefix(200)))")
        }

        var issues: [String] = []
        var warnings: [String] = []

        // Validate summary
        if let summary = json["summary"] as? String {
            if summary.isEmpty { warnings.append("summary is empty") }
        } else {
            warnings.append("summary field missing or not a string")
        }

        // Validate grades array
        guard let gradesArray = json["grades"] as? [[String: Any]] else {
            return (false, 0, nil, "Missing or invalid 'grades' array")
        }

        let validCategories: Set = ["thesis", "evidence", "organization", "style", "grammar", "clarity"]
        var validGrades: [(category: String, score: Int)] = []

        for (idx, item) in gradesArray.enumerated() {
            guard let catStr = item["category"] as? String else {
                issues.append("Grade \(idx): missing category")
                continue
            }
            let catLower = catStr.lowercased()
            if !validCategories.contains(catLower) {
                warnings.append("Grade \(idx): unknown category '\(catStr)'")
                continue
            }

            // Score can come as Int or Double from JSON
            let score: Int
            if let intScore = item["score"] as? Int {
                score = intScore
            } else if let dblScore = item["score"] as? Double {
                score = Int(dblScore)
            } else {
                issues.append("Grade \(idx) (\(catStr)): missing or invalid score")
                continue
            }

            if score < 0 || score > 100 {
                issues.append("Grade \(idx) (\(catStr)): score \(score) out of range 0-100")
            }

            if item["letterGrade"] as? String == nil {
                warnings.append("Grade \(idx) (\(catStr)): missing letterGrade")
            }
            if item["feedback"] as? String == nil {
                warnings.append("Grade \(idx) (\(catStr)): missing feedback")
            }

            validGrades.append((catLower, min(max(score, 0), 100)))
        }

        let avg: Int? = validGrades.isEmpty ? nil : validGrades.map(\.score).reduce(0, +) / validGrades.count
        let allNotes = (issues + warnings).joined(separator: "; ")
        return (issues.isEmpty && !validGrades.isEmpty, validGrades.count, avg, allNotes)
    }

    // MARK: - Reactions Validation

    /// Validate a reader reactions response (Review Panel — Reactions tab).
    static func validateReactionsResponse(
        _ response: String
    ) -> (valid: Bool, count: Int, notes: String) {
        guard let jsonString = extractJSONArray(from: response),
              let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return (false, 0, "Failed to extract JSON array. Raw prefix: \(String(response.prefix(200)))")
        }

        let validEmotions: Set = ["excited", "confused", "skeptical", "engaged", "bored", "inspired"]
        var issues: [String] = []
        var warnings: [String] = []
        var validCount = 0

        for (idx, item) in items.enumerated() {
            guard let title = item["sectionTitle"] as? String, !title.isEmpty else {
                issues.append("Item \(idx): missing or empty sectionTitle")
                continue
            }
            if let emotionStr = item["dominantEmotion"] as? String {
                if !validEmotions.contains(emotionStr.lowercased()) {
                    warnings.append("Item \(idx): unknown emotion '\(emotionStr)' (will default to engaged)")
                }
            } else {
                issues.append("Item \(idx): missing dominantEmotion")
                continue
            }
            if item["explanation"] as? String == nil {
                warnings.append("Item \(idx): missing explanation")
            }

            // Validate emotionScores if present
            if let scores = item["emotionScores"] as? [String: Any] {
                for (key, value) in scores {
                    if let scoreVal = value as? Int {
                        if scoreVal < 0 || scoreVal > 100 {
                            warnings.append("Item \(idx): emotion '\(key)' score \(scoreVal) out of 0-100")
                        }
                    }
                }
            }

            validCount += 1
        }

        let allNotes = (issues + warnings).joined(separator: "; ")
        return (issues.isEmpty && validCount > 0, validCount, allNotes)
    }
}
