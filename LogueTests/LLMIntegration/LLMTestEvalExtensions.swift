import Foundation
@testable import Logue

// MARK: - Fact Check, PII & Vocabulary Validation

extension LLMTestEval {
    // MARK: - Fact Check Validation

    /// Validate a fact check response (Verify Panel — Facts tab).
    static func validateFactCheckResponse(
        _ response: String
    ) -> (valid: Bool, count: Int, notes: String) {
        guard let jsonString = extractJSONArray(from: response),
              let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return (false, 0, "Failed to extract JSON array. Raw prefix: \(String(response.prefix(200)))")
        }

        let validStatuses: Set = ["verified", "unverified", "uncertain", "misleading"]
        var issues: [String] = []
        var warnings: [String] = []
        var validCount = 0

        for (idx, item) in items.enumerated() {
            guard let claim = item["claim"] as? String, !claim.isEmpty else {
                issues.append("Item \(idx): missing or empty claim")
                continue
            }
            if let statusStr = item["status"] as? String {
                if !validStatuses.contains(statusStr.lowercased()) {
                    warnings.append("Item \(idx): unknown status '\(statusStr)' (will default to uncertain)")
                }
            } else {
                issues.append("Item \(idx): missing status")
                continue
            }
            if item["explanation"] as? String == nil {
                warnings.append("Item \(idx): missing explanation")
            }

            // Validate confidence range
            if let conf = item["confidence"] as? Int {
                if conf < 0 || conf > 100 {
                    warnings.append("Item \(idx): confidence \(conf) out of 0-100 (will be clamped)")
                }
            } else if let confDbl = item["confidence"] as? Double {
                let confInt = Int(confDbl)
                if confInt < 0 || confInt > 100 {
                    warnings.append("Item \(idx): confidence \(confInt) out of 0-100 (will be clamped)")
                }
            }

            validCount += 1
        }

        let allNotes = (issues + warnings).joined(separator: "; ")
        return (issues.isEmpty && validCount > 0, validCount, allNotes)
    }

    // MARK: - PII Validation

    /// Validate a PII scan response (Verify Panel — Privacy tab).
    static func validatePIIResponse(
        _ response: String,
        enabledCategories: Set<PIICategory> = Set(PIICategory.allCases)
    ) -> (valid: Bool, count: Int, notes: String) {
        // Strip markdown fences and extract JSON
        let cleaned = stripMarkdownFences(from: response)
        // Find the first { or [ to determine format
        let firstBrace = cleaned.firstIndex(of: "{")
        let firstBracket = cleaned.firstIndex(of: "[")

        var findings: [PIIFinding] = []
        var parseNotes: [String] = []

        // Try PIIScanResponse format first: {"findings":[...]}
        if let fb = firstBrace, firstBracket.map({ fb < $0 }) ?? true {
            if let end = cleaned.lastIndex(of: "}") {
                let jsonStr = String(cleaned[fb ... end])
                if let data = jsonStr.data(using: .utf8),
                   let scanResponse = try? JSONDecoder().decode(PIIScanResponse.self, from: data)
                {
                    findings = scanResponse.findings
                    parseNotes.append("Parsed as PIIScanResponse")
                }
            }
        }

        // Fallback: try [PIIFinding] array
        if findings.isEmpty, let fb = firstBracket {
            if let end = cleaned.lastIndex(of: "]") {
                let jsonStr = String(cleaned[fb ... end])
                if let data = jsonStr.data(using: .utf8),
                   let items = try? JSONDecoder().decode([PIIFinding].self, from: data)
                {
                    findings = items
                    parseNotes.append("Parsed as [PIIFinding] array")
                }
            }
        }

        if findings.isEmpty, !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, 0, "Could not decode PII findings from response. Raw prefix: \(String(response.prefix(200)))")
        }

        // Filter to enabled categories
        let filtered = findings.filter { enabledCategories.contains($0.category) }

        // Validate each finding
        var issues: [String] = []
        for (idx, finding) in filtered.enumerated() {
            if finding.text.isEmpty {
                issues.append("Finding \(idx): empty text")
            }
            if finding.detail.isEmpty {
                issues.append("Finding \(idx): empty detail")
            }
        }

        let allNotes = (parseNotes + issues).joined(separator: "; ")
        return (issues.isEmpty, filtered.count, allNotes)
    }

    // MARK: - Vocabulary Validation

    /// Validate a vocabulary enhancement response.
    static func validateVocabResponse(
        _ response: String
    ) -> (valid: Bool, count: Int, notes: String) {
        guard let jsonString = extractJSONArray(from: response),
              let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return (false, 0, "Failed to extract JSON array. Raw prefix: \(String(response.prefix(200)))")
        }

        let validCategories: Set = ["overused", "weak", "informal", "imprecise", "repetitive"]
        var issues: [String] = []
        var warnings: [String] = []
        var validCount = 0
        let maxItems = 10

        if items.count > maxItems {
            warnings.append("Model returned \(items.count) suggestions; evaluating first \(maxItems)")
        }

        for (idx, item) in items.prefix(maxItems).enumerated() {
            guard let original = item["original"] as? String, !original.isEmpty else {
                issues.append("Item \(idx): missing or empty 'original'")
                continue
            }
            guard let suggestion = item["suggestion"] as? String, !suggestion.isEmpty else {
                issues.append("Item \(idx): missing or empty 'suggestion'")
                continue
            }

            if let category = item["category"] as? String {
                if !validCategories.contains(category.lowercased()) {
                    warnings.append("Item \(idx): unknown category '\(category)' (will default to 'weak')")
                }
            }

            validCount += 1
        }

        let allNotes = (issues + warnings).joined(separator: "; ")
        return (issues.isEmpty && (validCount > 0 || items.isEmpty), validCount, allNotes)
    }
}
