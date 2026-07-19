import Foundation
import MLXLMCommon
import os.log

// MARK: - CreateSpaceTool

/// Creates a new space (top-level or nested). Non-destructive.
struct CreateSpaceTool: AgentTool {
    let name = "create_space"
    let description = "Create a new space (folder) for organizing documents and meetings. Optionally nest under a parent space."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "name": AgentToolSpec.stringParam("Space name (1-100 chars)"),
                "parentID": AgentToolSpec.stringParam("UUID of parent space for nesting (optional)"),
            ],
            required: ["name"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let rawName = arguments["name"] as? String else {
            throw AgentToolError.missingParameter("name")
        }
        let name = String(rawName.prefix(100))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw AgentToolError.invalidParameter("name", "Name cannot be empty")
        }

        let parentID: UUID?
        if let idString = arguments["parentID"] as? String, !idString.isEmpty {
            guard let parsed = UUID(uuidString: idString) else {
                throw AgentToolError.invalidParameter("parentID", "Not a valid UUID")
            }
            let exists = await MainActor.run { SpaceStore.shared.space(for: parsed) != nil }
            guard exists else {
                throw AgentToolError.spaceNotFound(idString)
            }
            parentID = parsed
        } else {
            parentID = nil
        }

        let created: Space? = await MainActor.run {
            SpaceStore.shared.createSpace(name: name, parentID: parentID)
        }
        guard let created else {
            throw AgentToolError.executionFailed("Could not create space.")
        }

        var output = "Created space \"\(created.name)\""
        output += "\n   ID: \(created.id.uuidString)"
        if let parentID {
            output += "\n   Parent: \(parentID.uuidString)"
        }
        return output
    }
}

// MARK: - RenameSpaceTool

/// Renames a space. Destructive — changes user-visible structure.
struct RenameSpaceTool: AgentTool {
    let name = "rename_space"
    let description = "Rename an existing space. Changes the visible name in the sidebar. Requires user approval."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "spaceID": AgentToolSpec.stringParam("UUID of the space to rename"),
                "newName": AgentToolSpec.stringParam("New name for the space (1-100 chars)"),
            ],
            required: ["spaceID", "newName"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["spaceID"] as? String,
              let spaceID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("spaceID")
        }
        guard let rawName = arguments["newName"] as? String else {
            throw AgentToolError.missingParameter("newName")
        }
        let newName = String(rawName.prefix(100))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else {
            throw AgentToolError.invalidParameter("newName", "Name cannot be empty")
        }

        try await MainActor.run {
            let store = SpaceStore.shared
            guard store.space(for: spaceID) != nil else {
                throw AgentToolError.spaceNotFound(idString)
            }
            store.renameSpace(id: spaceID, newName: newName)
        }

        return "Renamed space \(spaceID.uuidString) to \"\(newName)\"."
    }
}

// MARK: - DeleteSpaceTool

/// Deletes a space and trashes all documents/meetings within it (and descendants).
/// Destructive.
struct DeleteSpaceTool: AgentTool {
    let name = "delete_space"
    let description = "Delete a space and trash all documents and meetings within it (and its child spaces). Requires user approval (Touch ID)."
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: ["spaceID": AgentToolSpec.stringParam("UUID of the space to delete")],
            required: ["spaceID"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let idString = arguments["spaceID"] as? String,
              let spaceID = UUID(uuidString: idString)
        else {
            throw AgentToolError.missingParameter("spaceID")
        }

        let name: String = try await MainActor.run {
            let store = SpaceStore.shared
            guard let space = store.space(for: spaceID) else {
                throw AgentToolError.spaceNotFound(idString)
            }
            store.deleteSpace(id: spaceID)
            return space.name
        }

        return "Deleted space \"\(name)\" and trashed its contents."
    }
}
