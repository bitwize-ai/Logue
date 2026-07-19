import Foundation
import MLXLMCommon
import os.log

// MARK: - Shared AI Tool Helpers

private enum AIToolHelpers {
    /// Sanitize document content for injection into an LLM prompt: trim, cap, strip nulls.
    static func sanitize(_ content: String, reservedTokens: Int) -> String {
        let maxChars = LLMEngine.maxInputChars(reservedTokens: reservedTokens)
        let capped = String(content.prefix(maxChars))
        return capped.filter { $0.asciiValue != 0 }
    }

    /// Fetch a document by UUID on the main actor. Throws `.documentNotFound` if missing.
    @MainActor
    static func fetchDocument(idString: String) throws -> WritingDocument {
        guard let id = UUID(uuidString: idString) else {
            throw AgentToolError.invalidParameter("documentID", "Not a valid UUID")
        }
        guard let doc = DocumentStore.shared.documents.first(where: { $0.id == id }) else {
            throw AgentToolError.documentNotFound(idString)
        }
        return doc
    }
}

// MARK: - SummarizeDocumentTool

/// Generates an AI summary of a document's body text.
struct SummarizeDocumentTool: AgentTool {
    let name = "summarize_document"
    let description = "Generate an AI summary of a document. Returns a short, medium, or long paragraph summary."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to summarize"),
                "length": AgentToolSpec.stringParam(
                    "Summary length (default: medium)",
                    enumValues: ["short", "medium", "long"]
                ),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }
        let length = (arguments["length"] as? String)?.lowercased() ?? "medium"
        let (maxTokens, guidance) = switch length {
        case "short": (256, "in 2-3 sentences")
        case "long": (1024, "in 5-8 paragraphs with detail")
        default: (512, "in 3-5 paragraphs")
        }

        let doc = try await MainActor.run {
            try AIToolHelpers.fetchDocument(idString: idString)
        }

        let body = AIToolHelpers.sanitize(doc.body, reservedTokens: maxTokens + 300)
        guard !body.isEmpty else {
            return "Document \"\(doc.title)\" is empty — nothing to summarize."
        }

        let system = "You are a concise technical writer. Summarize the provided content accurately and factually."
        let prompt = "Summarize the following document \(guidance).\n\n<content>\(body)</content>"

        let result = try await LLMEngine.shared.complete(
            system: system,
            prompt: prompt,
            temperature: 0.3,
            maxTokens: maxTokens
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentToolError.executionFailed("Model returned an empty summary.")
        }
        return "Summary of \"\(doc.title)\":\n\n\(trimmed)"
    }
}

// MARK: - RephraseTextTool

/// Rephrases arbitrary text in one of the built-in writing styles.
struct RephraseTextTool: AgentTool {
    let name = "rephrase_text"
    let description = "Rephrase a chunk of text in a specific writing style. Returns the rewritten text."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "text": AgentToolSpec.stringParam("Text to rephrase (1-10000 chars)"),
                "style": AgentToolSpec.stringParam(
                    "Target writing style",
                    enumValues: WritingGoalMode.allCases.map(\.rawValue)
                ),
            ],
            required: ["text", "style"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawText = arguments["text"] as? String else {
            throw AgentToolError.missingParameter("text")
        }
        guard let styleRaw = arguments["style"] as? String,
              let style = WritingGoalMode(rawValue: styleRaw.lowercased())
        else {
            let valid = WritingGoalMode.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentToolError.invalidParameter("style", "Must be one of: \(valid)")
        }

        let text = String(rawText.prefix(10000)).filter { $0.asciiValue != 0 }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidParameter("text", "Cannot be empty")
        }

        let result = try await LLMEngine.shared.rephrase(text, style: style)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentToolError.executionFailed("Model returned empty rephrased text.")
        }
        return "Rephrased (\(style.displayName)):\n\n\(trimmed)"
    }
}

// MARK: - GrammarCheckTool

/// Runs grammar/spelling/punctuation analysis on a document.
struct GrammarCheckTool: AgentTool {
    let name = "check_grammar"
    let description = "Run grammar and spelling analysis on a document. Returns a list of issues with suggested replacements."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to check"),
                "goalMode": AgentToolSpec.stringParam(
                    "Writing goal mode (default: casual)",
                    enumValues: WritingGoalMode.allCases.map(\.rawValue)
                ),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }
        let goalMode = (arguments["goalMode"] as? String).flatMap(WritingGoalMode.init(rawValue:)) ?? .casual

        let doc = try await MainActor.run {
            try AIToolHelpers.fetchDocument(idString: idString)
        }
        let body = AIToolHelpers.sanitize(doc.body, reservedTokens: 2048 + 256)
        guard !body.isEmpty else {
            return "Document \"\(doc.title)\" is empty — nothing to check."
        }

        let state = WritingAgentState([
            "text": body,
            "goal_mode": goalMode.rawValue,
            "context_window": body,
        ])
        let items = try await LLMEngine.shared.runGrammarCheck(state: state)
        return formatSuggestionItems(items, label: "Grammar", docTitle: doc.title, goalMode: goalMode)
    }
}

// MARK: - ClarityCheckTool

/// Runs clarity/conciseness/style analysis on a document.
struct ClarityCheckTool: AgentTool {
    let name = "check_clarity"
    let description = "Run clarity and style analysis on a document. Returns conciseness and wording suggestions."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to check"),
                "goalMode": AgentToolSpec.stringParam(
                    "Writing goal mode (default: casual)",
                    enumValues: WritingGoalMode.allCases.map(\.rawValue)
                ),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }
        let goalMode = (arguments["goalMode"] as? String).flatMap(WritingGoalMode.init(rawValue:)) ?? .casual

        let doc = try await MainActor.run {
            try AIToolHelpers.fetchDocument(idString: idString)
        }
        let body = AIToolHelpers.sanitize(doc.body, reservedTokens: 2048 + 256)
        guard !body.isEmpty else {
            return "Document \"\(doc.title)\" is empty — nothing to check."
        }

        let state = WritingAgentState([
            "text": body,
            "goal_mode": goalMode.rawValue,
            "context_window": body,
        ])
        let items = try await LLMEngine.shared.runClarityCheck(state: state)
        return formatSuggestionItems(items, label: "Clarity", docTitle: doc.title, goalMode: goalMode)
    }
}

// MARK: - ToneDetectTool

/// Detects the overall tone of a document.
struct ToneDetectTool: AgentTool {
    let name = "detect_tone"
    let description = "Detect the overall tone of a document (e.g. formal, casual, technical)."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document"),
                "goalMode": AgentToolSpec.stringParam(
                    "Writing goal mode (default: casual)",
                    enumValues: WritingGoalMode.allCases.map(\.rawValue)
                ),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String else {
            throw AgentToolError.missingParameter("documentID")
        }
        let goalMode = (arguments["goalMode"] as? String).flatMap(WritingGoalMode.init(rawValue:)) ?? .casual

        let doc = try await MainActor.run {
            try AIToolHelpers.fetchDocument(idString: idString)
        }
        let body = AIToolHelpers.sanitize(doc.body, reservedTokens: 256 + 256)
        guard !body.isEmpty else {
            return "Document \"\(doc.title)\" is empty — cannot detect tone."
        }

        let state = WritingAgentState([
            "text": body,
            "goal_mode": goalMode.rawValue,
            "context_window": body,
        ])
        let tone = try await LLMEngine.shared.runToneDetect(state: state)
        let pct = Int(tone.confidence * 100)
        return "Tone of \"\(doc.title)\": \(tone.label) (confidence \(pct)%)"
    }
}

// MARK: - Formatting Helpers

private func formatSuggestionItems(
    _ items: [SuggestionResponse.SuggestionItem],
    label: String,
    docTitle: String,
    goalMode: WritingGoalMode
) -> String {
    guard !items.isEmpty else {
        return "\(label) check on \"\(docTitle)\" (\(goalMode.displayName)): no issues found."
    }
    var output = "\(label) check on \"\(docTitle)\" (\(goalMode.displayName)) — \(items.count) issue(s):\n"
    for (index, item) in items.prefix(20).enumerated() {
        output += "\n\(index + 1). [\(item.type)] \"\(item.original)\" → \"\(item.replacement)\""
        output += "\n   \(item.explanation)"
    }
    if items.count > 20 {
        output += "\n\n... and \(items.count - 20) more."
    }
    return output
}
