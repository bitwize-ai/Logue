import Foundation
import MLXLMCommon
import os.log

// MARK: - ListTemplatesTool

/// Lists built-in and user-created document templates, optionally filtered by category.
struct ListTemplatesTool: AgentTool {
    let name = "list_templates"
    let description = "List available document templates. Optionally filter by category."
    let clearance: ToolClearance = .regular

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "category": AgentToolSpec.stringParam(
                    "Template category (optional)",
                    enumValues: TemplateCategory.allCases.map(\.rawValue)
                ),
            ]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let categoryFilter = (arguments["category"] as? String).flatMap(TemplateCategory.init(rawValue:))

        let templates: [DocumentTemplate] = await MainActor.run {
            let all = TemplateStore.shared.templates
            guard let categoryFilter else { return all }
            return all.filter { $0.category == categoryFilter }
        }

        guard !templates.isEmpty else {
            if let categoryFilter {
                return "No templates found in category \"\(categoryFilter.rawValue)\"."
            }
            return "No templates available."
        }

        // Group by category for readability
        let grouped = Dictionary(grouping: templates, by: \.category)
        var output = "\(templates.count) template(s):\n"
        for category in TemplateCategory.allCases {
            guard let list = grouped[category], !list.isEmpty else { continue }
            output += "\n[\(category.rawValue)] (\(list.count)):\n"
            for tmpl in list.prefix(8) {
                output += "  - \"\(tmpl.name)\""
                output += "  (ID: \(tmpl.id.uuidString))"
                if !tmpl.description.isEmpty {
                    output += "\n    \(tmpl.description)"
                }
                output += "\n"
            }
            if list.count > 8 {
                output += "  ... and \(list.count - 8) more\n"
            }
        }
        return output
    }
}

// MARK: - CreateDocumentFromTemplateTool

/// Instantiates a new document from a template's body. Non-destructive.
struct CreateDocumentFromTemplateTool: AgentTool {
    let name = "create_document_from_template"
    let description = "Create a new document pre-populated from a template's body. Returns the new document ID."
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "templateID": AgentToolSpec.stringParam("UUID of the template to instantiate"),
                "title": AgentToolSpec.stringParam("Title for the new document (1-200 chars)"),
                "spaceID": AgentToolSpec.stringParam("Target space UUID (optional)"),
            ],
            required: ["templateID", "title"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let tmplIDString = arguments["templateID"] as? String,
              let templateID = UUID(uuidString: tmplIDString)
        else {
            throw AgentToolError.missingParameter("templateID")
        }
        guard let rawTitle = arguments["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let title = String(rawTitle.prefix(200))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            throw AgentToolError.invalidParameter("title", "Title cannot be empty")
        }

        let spaceID: UUID?
        if let idString = arguments["spaceID"] as? String, !idString.isEmpty {
            guard let parsed = UUID(uuidString: idString) else {
                throw AgentToolError.invalidParameter("spaceID", "Not a valid UUID")
            }
            let exists = await MainActor.run { SpaceStore.shared.space(for: parsed) != nil }
            guard exists else { throw AgentToolError.spaceNotFound(idString) }
            spaceID = parsed
        } else {
            spaceID = nil
        }

        let newDoc: WritingDocument = try await MainActor.run {
            guard let template = TemplateStore.shared.template(for: templateID) else {
                throw AgentToolError.templateNotFound(tmplIDString)
            }
            return DocumentStore.shared.createDocument(
                title: title,
                body: template.body,
                inSpace: spaceID,
                select: false
            )
        }

        var output = "Created document \"\(newDoc.title)\" from template \(templateID.uuidString)"
        output += "\n   ID: \(newDoc.id.uuidString)"
        if let spaceID {
            output += "\n   Space: \(spaceID.uuidString)"
        }
        return output
    }
}
