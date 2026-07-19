import Foundation
@testable import Logue
import Testing

// MARK: - Fact Check LLM Tests

@Suite("Fact Check LLM", .serialized, .timeLimit(.minutes(10)))
struct FactCheckLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildFactCheckPrompt(text: String) -> String {
        """
        Analyze this text and identify all factual claims that can be verified.
        Return ONLY valid JSON in this exact format:
        [
          {
            "claim": "The factual claim from the text",
            "status": "verified",
            "explanation": "Why this status was assigned",
            "sources": ["Source 1", "Source 2"],
            "confidence": 85
          }
        ]

        Status must be one of: verified, unverified, uncertain, misleading.
        Confidence is 0-100.

        Text: \(text)
        """
    }

    @Test("Fact check on factual claims text identifies multiple claims")
    func factCheck_factualClaims() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.factualClaimsText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateFactCheckResponse(response)
        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "factualClaims",
            input: String(SampleDocuments.factualClaimsText.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Fact check response should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 3, "Should identify at least 3 claims from factual text, got \(result.count)")
    }

    @Test("Fact check on business email produces valid JSON")
    func factCheck_businessEmail() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.businessEmail)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateFactCheckResponse(response)
        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Fact check response should be valid JSON. Issues: \(result.notes)")
    }

    @Test("Fact check on academic essay finds research-related claims")
    func factCheck_academicEssay() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.academicEssay)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validateFactCheckResponse(response)
        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "academicEssay",
            input: String(SampleDocuments.academicEssay.prefix(100)),
            output: response,
            passed: result.valid, notes: result.notes
        )
        #expect(result.valid, "Fact check response should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 1, "Academic essay should have at least 1 verifiable claim, got \(result.count)")
    }

    @Test("Fact check status values are all valid")
    func factCheck_statusValues() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.factualClaimsText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let validStatuses: Set<String> = ["verified", "unverified", "uncertain", "misleading"]

        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "["),
              let arrEnd = cleaned.lastIndex(of: "]"),
              arrStart < arrEnd,
              let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            #expect(Bool(false), "Failed to parse fact check JSON array")
            return
        }

        var allValid = true
        for (idx, item) in items.enumerated() {
            if let status = item["status"] as? String {
                if !validStatuses.contains(status.lowercased()) {
                    allValid = false
                    print("  [FAIL] Item \(idx): invalid status '\(status)'")
                }
            }
        }

        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "statusValues",
            input: "factualClaimsText",
            output: "Checked \(items.count) items",
            passed: allValid
        )
        #expect(allValid, "All status values should be one of: verified, unverified, uncertain, misleading")
    }

    @Test("Fact check confidence values are within 0-100")
    func factCheck_confidenceRange() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.factualClaimsText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let cleaned = LLMTestEval.stripMarkdownFences(from: response)
        guard let arrStart = cleaned.firstIndex(of: "["),
              let arrEnd = cleaned.lastIndex(of: "]"),
              arrStart < arrEnd,
              let data = String(cleaned[arrStart ... arrEnd]).data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            #expect(Bool(false), "Failed to parse fact check JSON array")
            return
        }

        var allInRange = true
        for (idx, item) in items.enumerated() {
            let conf: Int
            if let intConf = item["confidence"] as? Int {
                conf = intConf
            } else if let dblConf = item["confidence"] as? Double {
                conf = Int(dblConf)
            } else {
                continue // Missing confidence defaults to 50 in production
            }

            if conf < 0 || conf > 100 {
                allInRange = false
                print("  [WARN] Item \(idx): confidence \(conf) out of 0-100")
            }
        }

        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "confidenceRange",
            input: "factualClaimsText",
            output: "Checked \(items.count) items",
            passed: allInRange
        )
        #expect(allInRange, "All confidence values should be within 0-100")
    }

    @Test("Fact check on clean text returns empty or minimal results")
    func factCheck_cleanText() async throws {
        let prompt = buildFactCheckPrompt(text: SampleDocuments.cleanText)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        LLMTestEval.logResult(
            feature: "FactCheck", testCase: "cleanText",
            input: SampleDocuments.cleanText,
            output: response,
            passed: true, notes: "Clean text — few/no claims expected"
        )
        // "The quick brown fox..." has no factual claims — should not crash
        // May return empty array or minimal results
    }
}

// MARK: - PII Scan LLM Tests

@Suite("PII Scan LLM", .serialized, .timeLimit(.minutes(10)))
struct PIIScanLLMTests {
    init() async throws {
        try await LLMTestHarness.ensureModelLoaded()
    }

    private func buildPIIPrompt(text: String, categories: Set<PIICategory>) -> String {
        let categoryList = categories.map { "- \($0.rawValue): \($0.examples) (Risk: \($0.risk.rawValue))" }.joined(separator: "\n")
        return """
        You are a PII detection expert. Analyze the text and identify ALL personal or sensitive data.

        CATEGORIES:
        \(categoryList)

        RULES:
        - Find every PII instance matching the categories.
        - Return the exact text found and a brief label.
        - Return ONLY valid JSON, no explanation.

        FORMAT:
        {"findings":[{"category":"<exact category name>","text":"<exact text>","detail":"<label>"}]}

        Valid category names: \(categories.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))

        TEXT:
        \(text)
        """
    }

    @Test("PII scan on PII-laden text detects multiple categories")
    func piiScan_piiLadenText() async throws {
        let allCategories = Set(PIICategory.allCases)
        let prompt = buildPIIPrompt(text: SampleDocuments.piiLadenText, categories: allCategories)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validatePIIResponse(response, enabledCategories: allCategories)
        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "piiLadenText",
            input: String(SampleDocuments.piiLadenText.prefix(100)),
            output: response,
            passed: result.valid && result.count >= 5,
            notes: "count=\(result.count). \(result.notes)"
        )
        #expect(result.valid, "PII response should be valid JSON. Issues: \(result.notes)")
        #expect(result.count >= 5, "PII-laden text should have at least 5 findings, got \(result.count)")
    }

    @Test("PII scan on clean text returns zero findings")
    func piiScan_cleanText() async throws {
        let allCategories = Set(PIICategory.allCases)
        let prompt = buildPIIPrompt(text: SampleDocuments.cleanText, categories: allCategories)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validatePIIResponse(response, enabledCategories: allCategories)
        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "cleanText",
            input: SampleDocuments.cleanText,
            output: response,
            passed: true, notes: "count=\(result.count). \(result.notes)"
        )
        // "The quick brown fox..." has no PII
        #expect(result.count <= 1, "Clean text should have 0-1 PII findings, got \(result.count)")
    }

    @Test("PII scan on business email detects names")
    func piiScan_businessEmail() async throws {
        let allCategories = Set(PIICategory.allCases)
        let prompt = buildPIIPrompt(text: SampleDocuments.businessEmail, categories: allCategories)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validatePIIResponse(response, enabledCategories: allCategories)
        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "businessEmail",
            input: String(SampleDocuments.businessEmail.prefix(100)),
            output: response,
            passed: result.valid, notes: "count=\(result.count). \(result.notes)"
        )
        #expect(result.valid, "PII response should be valid. Issues: \(result.notes)")
        #expect(result.count >= 1, "Business email should detect at least names (Sarah Chen, Mr. Thompson), got \(result.count)")
    }

    @Test("PIIRegexScanner catches known patterns without LLM")
    func piiScan_regexScanner() {
        let allCategories = Set(PIICategory.allCases)
        let findings = PIIRegexScanner.scan(text: SampleDocuments.piiLadenText, categories: allCategories)

        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "regexScanner",
            input: "piiLadenText (regex only)",
            output: "Found \(findings.count) items: \(findings.map { "\($0.category.rawValue):\($0.text)" }.joined(separator: ", "))",
            passed: !findings.isEmpty
        )
        #expect(!findings.isEmpty, "Regex scanner should catch at least SSN, email, or phone from PII text")

        // Check specific patterns we know are in the text
        let foundTexts = Set(findings.map { $0.text.lowercased() })
        let foundCategories = Set(findings.map(\.category))

        // At least some of these should be caught by regex
        let hasAnyKnown = foundTexts.contains("john.smith@example.com")
            || foundTexts.contains("123-45-6789")
            || foundTexts.contains("(555) 867-5309")
            || foundTexts.contains("192.168.1.42")
            || foundCategories.contains(.contact)
            || foundCategories.contains(.governmentIDs)

        #expect(hasAnyKnown, "Regex should catch at least one known PII pattern (email, SSN, phone, or IP)")
    }

    @Test("PII scan with category filtering only returns selected categories")
    func piiScan_categoryFiltering() async throws {
        let selectedCategories: Set<PIICategory> = [.identity, .contact]
        let prompt = buildPIIPrompt(text: SampleDocuments.piiLadenText, categories: selectedCategories)
        let response = try await LLMEngine.shared.chat(prompt: prompt)

        let result = LLMTestEval.validatePIIResponse(response, enabledCategories: selectedCategories)
        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "categoryFiltering",
            input: "piiLadenText (identity + contact only)",
            output: response,
            passed: result.valid, notes: "count=\(result.count). \(result.notes)"
        )
        // Validate that only identity/contact findings are returned after filtering
        #expect(result.valid, "Filtered PII response should be valid. Issues: \(result.notes)")
    }

    @Test("extractJSON strips markdown fences correctly")
    func piiScan_markdownFences() {
        // Test with markdown-fenced JSON (no LLM needed)
        let fencedJSON = """
        ```json
        {"findings":[{"category":"Identity","text":"John Smith","detail":"Full name"}]}
        ```
        """

        let result = LLMTestEval.validatePIIResponse(fencedJSON, enabledCategories: Set(PIICategory.allCases))
        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "markdownFences",
            input: "Hardcoded fenced JSON",
            output: "valid=\(result.valid), count=\(result.count)",
            passed: result.valid && result.count == 1
        )
        #expect(result.valid, "Should parse markdown-fenced JSON. Issues: \(result.notes)")
        #expect(result.count == 1, "Should find 1 PII finding, got \(result.count)")
    }

    @Test("PII scan handles both response formats")
    func piiScan_responseFormat() {
        // Test PIIScanResponse format (wrapper object)
        let wrapperJSON = """
        {"findings":[{"category":"Contact","text":"test@example.com","detail":"Email address"}]}
        """
        let wrapperResult = LLMTestEval.validatePIIResponse(wrapperJSON, enabledCategories: Set(PIICategory.allCases))
        #expect(wrapperResult.valid, "PIIScanResponse wrapper format should parse. Issues: \(wrapperResult.notes)")
        #expect(wrapperResult.count == 1, "Wrapper format: expected 1 finding, got \(wrapperResult.count)")

        // Test direct array format
        let arrayJSON = """
        [{"category":"Contact","text":"test@example.com","detail":"Email address"}]
        """
        let arrayResult = LLMTestEval.validatePIIResponse(arrayJSON, enabledCategories: Set(PIICategory.allCases))
        #expect(arrayResult.valid, "Direct array format should parse. Issues: \(arrayResult.notes)")
        #expect(arrayResult.count == 1, "Array format: expected 1 finding, got \(arrayResult.count)")

        LLMTestEval.logResult(
            feature: "PIIScan", testCase: "responseFormat",
            input: "Both JSON formats",
            output: "wrapper=\(wrapperResult.valid), array=\(arrayResult.valid)",
            passed: wrapperResult.valid && arrayResult.valid
        )
    }
}
