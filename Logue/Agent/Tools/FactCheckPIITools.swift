import Foundation
import MLXLMCommon
import os.log

// MARK: - FactCheckDocumentTool

/// Runs fact-check analysis on a document via LLM, reusing the VerifyPanel prompt.
struct FactCheckDocumentTool: AgentTool {
    let name = "fact_check_document"
    let description = "Identify factual claims in a document and rate each as verified, unverified, uncertain, or misleading."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["documentID": AgentToolSpec.stringParam("UUID of the document")],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }

        let doc = try await MainActor.run {
            try fetchDocument(idString: idString)
        }

        let maxChars = LLMEngine.maxInputChars(reservedTokens: 1024 + 300)
        let body = String(doc.body.prefix(maxChars)).filter { $0.asciiValue != 0 }
        guard !body.isEmpty else {
            return "Document \"\(doc.title)\" is empty — nothing to fact-check."
        }

        let prompt = PromptRegistry.Verification.factCheckPrompt(text: body)
        let system = "You are a fact-verification assistant. Output ONLY the requested JSON array."

        let response = try await LLMEngine.shared.complete(
            system: system,
            prompt: prompt,
            temperature: 0.2,
            maxTokens: 1024
        )

        let items = parseFactChecks(response)
        guard !items.isEmpty else {
            return "No factual claims identified in \"\(doc.title)\"."
        }

        var output = "Fact check on \"\(doc.title)\" — \(items.count) claim(s):\n"
        for (index, item) in items.enumerated() {
            output += "\n\(index + 1). [\(item.status)] \(item.claim)"
            output += "\n   Confidence: \(item.confidence)%"
            output += "\n   \(item.explanation)"
            if !item.sources.isEmpty {
                output += "\n   Sources: \(item.sources.joined(separator: "; "))"
            }
        }
        return output
    }

    // MARK: - Parsing

    private struct ParsedClaim {
        let claim: String
        let status: String
        let explanation: String
        let sources: [String]
        let confidence: Int
    }

    private func parseFactChecks(_ text: String) -> [ParsedClaim] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Locate the JSON array
        guard let arrayStart = cleaned.firstIndex(of: "["),
              let arrayEnd = cleaned.lastIndex(of: "]"),
              arrayEnd > arrayStart
        else { return [] }

        let jsonSlice = String(cleaned[arrayStart ... arrayEnd])
        guard let data = jsonSlice.data(using: .utf8) else { return [] }

        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> ParsedClaim? in
            guard let claim = item["claim"] as? String,
                  let status = item["status"] as? String,
                  let explanation = item["explanation"] as? String
            else { return nil }
            let sources = item["sources"] as? [String] ?? []
            let confidence = min(max(item["confidence"] as? Int ?? 50, 0), 100)
            return ParsedClaim(
                claim: claim, status: status.lowercased(),
                explanation: explanation, sources: sources, confidence: confidence
            )
        }
    }

    @MainActor
    private func fetchDocument(idString: String) throws -> WritingDocument {
        guard let id = UUID(uuidString: idString) else {
            throw AgentToolError.invalidParameter("documentID", "Not a valid UUID")
        }
        guard let doc = DocumentStore.shared.documents.first(where: { $0.id == id }) else {
            throw AgentToolError.documentNotFound(idString)
        }
        return doc
    }
}

// MARK: - DetectPIITool

/// Scans a document for PII via regex + LLM enrichment, reusing the VerifyPanel pipeline.
struct DetectPIITool: AgentTool {
    let name = "detect_pii"
    let description = "Scan a document for personal or sensitive data (PII) like emails, phone numbers, IDs, credentials, health data."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document"),
                "categories": AgentToolSpec.stringArrayParam(
                    "PII categories to scan (defaults to all). Valid: "
                        + PIICategory.allCases.map(\.rawValue).joined(separator: ", ")
                ),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }

        let categories: Set<PIICategory>
        if let rawCategories = arguments["categories"] as? [String], !rawCategories.isEmpty {
            let parsed = rawCategories.compactMap(PIICategory.init(rawValue:))
            guard !parsed.isEmpty else {
                throw AgentToolError.invalidParameter(
                    "categories",
                    "None of the supplied categories are recognised"
                )
            }
            categories = Set(parsed)
        } else {
            categories = Set(PIICategory.allCases)
        }

        let doc = try await MainActor.run {
            try fetchDocument(idString: idString)
        }

        let scanText = String(doc.body.prefix(6000)).filter { $0.asciiValue != 0 }
        guard !scanText.isEmpty else {
            return "Document \"\(doc.title)\" is empty — nothing to scan."
        }

        let regexFindings = PIIRegexScanner.scan(text: scanText, categories: categories)

        // LLM enrichment — contextual PII regex alone can miss
        var merged = regexFindings
        let llmText = String(scanText.prefix(3000))
        let system = PromptRegistry.Verification.piiSystemPrompt(categories: categories)
        let prompt = "<categories>\(categories.map(\.rawValue).joined(separator: ", "))</categories>\n\nTEXT:\n<content>\(llmText)</content>"

        do {
            let response = try await LLMEngine.shared.complete(
                system: system,
                prompt: prompt,
                temperature: 0.1,
                maxTokens: 1024
            )
            let llmFindings = parsePIIFindings(from: response, enabled: categories)
            let existingTexts = Set(regexFindings.map { $0.text.lowercased() })
            for finding in llmFindings where !existingTexts.contains(finding.text.lowercased()) {
                merged.append(finding)
            }
        } catch {
            // Regex results are still valid even if LLM fails
        }

        guard !merged.isEmpty else {
            return "No PII detected in \"\(doc.title)\"."
        }

        // Group by category for readability
        let grouped = Dictionary(grouping: merged, by: \.category)
        var output = "PII scan on \"\(doc.title)\" — \(merged.count) finding(s) across \(grouped.count) categor(ies):\n"
        for category in PIICategory.allCases {
            guard let findings = grouped[category], !findings.isEmpty else { continue }
            output += "\n[\(category.rawValue)] (\(findings.count), risk: \(category.risk.rawValue))"
            for finding in findings.prefix(10) {
                output += "\n  - \"\(finding.text)\" — \(finding.detail)"
            }
            if findings.count > 10 {
                output += "\n  ... and \(findings.count - 10) more"
            }
        }
        return output
    }

    // MARK: - Parsing

    private func parsePIIFindings(from response: String, enabled: Set<PIICategory>) -> [PIIFinding] {
        // Strip fences and isolate the JSON object
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let objStart = cleaned.firstIndex(of: "{"),
              let objEnd = cleaned.lastIndex(of: "}"),
              objEnd > objStart
        else { return [] }
        let jsonSlice = String(cleaned[objStart ... objEnd])
        guard let data = jsonSlice.data(using: .utf8) else { return [] }

        struct ScanResponse: Codable { let findings: [PIIFinding] }
        if let parsed = try? JSONDecoder().decode(ScanResponse.self, from: data) {
            return parsed.findings.filter { enabled.contains($0.category) }
        }
        return []
    }

    @MainActor
    private func fetchDocument(idString: String) throws -> WritingDocument {
        guard let id = UUID(uuidString: idString) else {
            throw AgentToolError.invalidParameter("documentID", "Not a valid UUID")
        }
        guard let doc = DocumentStore.shared.documents.first(where: { $0.id == id }) else {
            throw AgentToolError.documentNotFound(idString)
        }
        return doc
    }
}
