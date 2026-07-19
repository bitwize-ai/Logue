import Foundation
import MLXLMCommon
import os.log

// MARK: - Argument Sanitization

private enum AgentArgs {
    /// Trim, cap to `maxLen`, strip control chars. Use on any user-derived string before
    /// storing it as a document/space title or embedding in an LLM prompt.
    static func sanitize(_ value: String, maxLen: Int = 200) -> String {
        String(value.prefix(maxLen)).filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Trim only — keeps newlines / unicode. Use for document body text.
    static func trim(_ value: String, maxLen: Int) -> String {
        String(value.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - CreateDocumentTool

/// Creates a new document. Non-destructive — new content is always reversible via trash.
struct CreateDocumentTool: AgentTool {
    let name = "create_document"
    let description = "Create a new document with a title and optional body text and space. Returns the new document ID."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "title": AgentToolSpec.stringParam("Document title (1-200 chars)"),
                "body": AgentToolSpec.stringParam("Document body content (optional)"),
                "spaceID": AgentToolSpec.stringParam("UUID of the space to put the document in (optional)"),
            ],
            required: ["title"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawTitle = arguments["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let title = AgentArgs.sanitize(rawTitle)
        guard !title.isEmpty else {
            throw AgentToolError.invalidParameter("title", "Title cannot be empty")
        }

        // Cap body to fit one context window — the agent can refuse huge pastes anyway
        let body = AgentArgs.trim((arguments["body"] as? String) ?? "", maxLen: 50000)

        let spaceID: UUID?
        if let idString = arguments["spaceID"] as? String, !idString.isEmpty {
            guard let parsed = UUID(uuidString: idString) else {
                throw AgentToolError.invalidParameter("spaceID", "Not a valid UUID")
            }
            // Verify space exists
            let exists = await MainActor.run {
                SpaceStore.shared.space(for: parsed) != nil
            }
            guard exists else {
                throw AgentToolError.spaceNotFound(idString)
            }
            spaceID = parsed
        } else {
            spaceID = nil
        }

        let newDoc = await MainActor.run {
            DocumentStore.shared.createDocument(title: title, body: body, inSpace: spaceID, select: false)
        }

        var output = "Created document \"\(newDoc.title)\""
        output += "\n   ID: \(newDoc.id.uuidString)"
        if let spaceID {
            output += "\n   Space: \(spaceID.uuidString)"
        }
        return output
    }
}

// MARK: - UpdateDocumentTool

/// Overwrites a document's body (and optionally its title). Destructive.
struct UpdateDocumentTool: AgentTool {
    let name = "update_document"
    let description = "Update an existing document's body text, and optionally its title. Overwrites current content — requires user approval."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to update"),
                "body": AgentToolSpec.stringParam("New document body content"),
                "title": AgentToolSpec.stringParam("New title (optional, leave empty to keep current)"),
            ],
            required: ["documentID", "body"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String,
              let documentID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("documentID")
        }
        guard let newBody = arguments["body"] as? String else {
            throw AgentToolError.missingParameter("body")
        }
        let trimmedBody = AgentArgs.trim(newBody, maxLen: 100_000)
        let newTitle = (arguments["title"] as? String).map { AgentArgs.sanitize($0) }

        try await MainActor.run {
            let store = DocumentStore.shared
            guard var doc = store.documents.first(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            doc.body = trimmedBody
            if let newTitle, !newTitle.isEmpty {
                doc.title = newTitle
            }
            store.updateDocument(doc)
        }

        return "Updated document \(documentID.uuidString) (\(trimmedBody.count) chars)."
    }
}

// MARK: - DeleteDocumentTool

/// Soft-deletes a document to trash. Destructive.
struct DeleteDocumentTool: AgentTool {
    let name = "delete_document"
    let description = "Move a document to trash. The user can restore it later. Requires user approval (Touch ID)."
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["documentID": AgentToolSpec.stringParam("UUID of the document to delete")],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String,
              let documentID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("documentID")
        }

        let title: String = try await MainActor.run {
            let store = DocumentStore.shared
            guard let doc = store.documents.first(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            store.deleteDocument(id: documentID)
            return doc.title
        }

        return "Moved \"\(title)\" to trash."
    }
}

// MARK: - MoveDocumentTool

/// Moves a document into a space (or removes it from any space if `toSpaceID` is empty).
/// Non-destructive — move is fully reversible.
struct MoveDocumentTool: AgentTool {
    let name = "move_document"
    let description = "Move a document to a different space. Pass an empty toSpaceID to remove the document from any space."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to move"),
                "toSpaceID": AgentToolSpec.stringParam("UUID of target space, or empty string to unfile"),
            ],
            required: ["documentID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String,
              let documentID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("documentID")
        }

        let targetSpaceID: UUID?
        if let toSpace = arguments["toSpaceID"] as? String, !toSpace.isEmpty {
            guard let parsed = UUID(uuidString: toSpace) else {
                throw AgentToolError.invalidParameter("toSpaceID", "Not a valid UUID")
            }
            targetSpaceID = parsed
        } else {
            targetSpaceID = nil
        }

        try await MainActor.run {
            let docStore = DocumentStore.shared
            guard docStore.documents.contains(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            if let targetSpaceID, SpaceStore.shared.space(for: targetSpaceID) == nil {
                throw AgentToolError.spaceNotFound(targetSpaceID.uuidString)
            }
            docStore.moveDocument(id: documentID, toSpace: targetSpaceID)
        }

        if let targetSpaceID {
            return "Moved document \(documentID.uuidString) to space \(targetSpaceID.uuidString)."
        }
        return "Removed document \(documentID.uuidString) from its space."
    }
}

// MARK: - AddDocumentTagTool

/// Adds a tag to a document. Non-destructive.
struct AddDocumentTagTool: AgentTool {
    let name = "add_document_tag"
    let description = "Add a tag to a document. Tags help with search and organization."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document"),
                "tag": AgentToolSpec.stringParam("Tag to add (1-60 chars)"),
            ],
            required: ["documentID", "tag"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["documentID"] as? String,
              let documentID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("documentID")
        }
        guard let rawTag = arguments["tag"] as? String else {
            throw AgentToolError.missingParameter("tag")
        }
        let tag = AgentArgs.sanitize(rawTag, maxLen: 60)
        guard !tag.isEmpty else {
            throw AgentToolError.invalidParameter("tag", "Tag cannot be empty")
        }

        try await MainActor.run {
            let store = DocumentStore.shared
            guard store.documents.contains(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            store.addTag(tag, to: documentID)
        }

        return "Added tag \"\(tag)\" to document \(documentID.uuidString)."
    }
}
