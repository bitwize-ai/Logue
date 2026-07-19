import Foundation
import MLXLMCommon
import os.log

// MARK: - ListDocumentsTool

/// Lists all active (non-trashed) documents with title, date, and a brief preview.
struct ListDocumentsTool: AgentTool {
    let name = "list_documents"
    let description = "List all available documents with their titles, IDs, and dates."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(name: name, description: description)
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let docs = await MainActor.run {
            DocumentStore.shared.activeDocuments.sorted { $0.modifiedAt > $1.modifiedAt }
        }

        guard !docs.isEmpty else {
            return "No documents found."
        }

        var output = "\(docs.count) document(s):\n"
        for (index, doc) in docs.enumerated() {
            let preview = String(doc.body.prefix(80))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            output += "\n\(index + 1). \(doc.title)"
            output += "\n   ID: \(doc.id.uuidString)"
            output += "\n   Modified: \(doc.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
            if !preview.isEmpty {
                output += "\n   Preview: \(preview)"
            }
        }
        return output
    }
}

// MARK: - SearchDocumentsTool

/// Searches documents by title and content keywords.
struct SearchDocumentsTool: AgentTool {
    let name = "search_documents"
    let description = "Search documents by title or content keywords. Returns matching documents with titles and content previews."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "query": AgentToolSpec.stringParam("Search keywords"),
                "limit": AgentToolSpec.intParam("Maximum results (default 5, max 10)"),
            ],
            required: ["query"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = min((arguments["limit"] as? Int) ?? 5, 10)

        let queryLower = query.lowercased()
        let matches = await MainActor.run {
            Array(DocumentStore.shared.activeDocuments.filter { doc in
                doc.title.lowercased().contains(queryLower)
                    || doc.body.lowercased().contains(queryLower)
            }
            .prefix(limit))
        }

        guard !matches.isEmpty else {
            return "No documents found matching \"\(query)\"."
        }

        var output = "Found \(matches.count) document(s) matching \"\(query)\":\n"
        for (index, doc) in matches.enumerated() {
            output += "\n\(index + 1). \(doc.title)"
            output += "\n   ID: \(doc.id.uuidString)"
            output += "\n   Modified: \(doc.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
            let preview = String(doc.body.prefix(100)).replacingOccurrences(of: "\n", with: " ")
            if !preview.isEmpty {
                output += "\n   Preview: \(preview)"
            }
        }
        return output
    }
}

// MARK: - GetDocumentTool

/// Retrieves the full content of a specific document by ID.
struct GetDocumentTool: AgentTool {
    let name = "get_document"
    let description = "Get the full content of a specific document by ID. Returns title, body text, and metadata."
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
        guard let idString = arguments["documentID"] as? String,
              let documentID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("documentID")
        }

        let doc: WritingDocument = try await MainActor.run {
            let store = DocumentStore.shared
            guard let doc = store.documents.first(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            return doc
        }

        var output = "Document: \(doc.title)\n"
        output += "Created: \(doc.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
        output += "Modified: \(doc.modifiedAt.formatted(date: .abbreviated, time: .shortened))\n"

        if let spaceID = doc.spaceID {
            output += "Space ID: \(spaceID.uuidString)\n"
        }

        // Truncate body to fit context window
        let maxChars = AppConstants.AgentDefaults.toolResultMaxChars
        let body = String(doc.body.prefix(maxChars))
        output += "\nContent:\n<content>\(body)</content>\n"

        if doc.body.count > maxChars {
            output += "\n[Content truncated — showing first \(maxChars) characters of \(doc.body.count) total]"
        }

        return output
    }
}
