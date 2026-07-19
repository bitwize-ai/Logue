import Foundation
import os.log

/// Central observable template store. Persists user-created templates to Application Support as JSON.
/// Built-in templates are loaded on first launch and cannot be deleted by the user.
@Observable
@MainActor
final class TemplateStore {
    static let shared = TemplateStore()
    private init() {
        Task { await loadFromDiskAsync() }
    }

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "TemplateStore")

    // MARK: - State

    var templates: [DocumentTemplate] = []
    private(set) var isLoaded = false

    // MARK: - Queries

    var builtInTemplates: [DocumentTemplate] {
        templates.filter(\.isBuiltIn)
    }

    var userTemplates: [DocumentTemplate] {
        templates.filter { !$0.isBuiltIn }
    }

    func templates(in category: TemplateCategory) -> [DocumentTemplate] {
        templates.filter { $0.category == category }
    }

    func template(for id: UUID) -> DocumentTemplate? {
        templates.first { $0.id == id }
    }

    // MARK: - CRUD

    @discardableResult
    func createTemplate(
        name: String,
        category: TemplateCategory,
        icon: String,
        description: String,
        body: String
    ) -> DocumentTemplate {
        let template = DocumentTemplate(
            name: name,
            category: category,
            icon: icon,
            description: description,
            body: body,
            isBuiltIn: false
        )
        templates.append(template)
        saveToDisk()
        return template
    }

    func updateTemplate(_ updated: DocumentTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == updated.id }) else { return }
        templates[index] = updated
        saveToDisk()
    }

    func deleteTemplate(id: UUID) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        // Don't allow deleting built-in templates
        guard !templates[index].isBuiltIn else { return }
        templates.remove(at: index)
        saveToDisk()
    }

    /// Create a template from an existing document.
    @discardableResult
    func saveDocumentAsTemplate(
        title: String,
        body: String,
        category: TemplateCategory,
        icon: String = "doc.text",
        description: String = ""
    ) -> DocumentTemplate {
        createTemplate(
            name: title,
            category: category,
            icon: icon,
            description: description,
            body: body
        )
    }

    /// Import a Markdown file as a new template.
    @discardableResult
    func importMarkdownAsTemplate(
        url: URL,
        name: String,
        category: TemplateCategory,
        icon: String = "doc.text",
        description: String = ""
    ) throws -> DocumentTemplate {
        let body = try String(contentsOf: url, encoding: .utf8)
        return createTemplate(
            name: name,
            category: category,
            icon: icon,
            description: description,
            body: body
        )
    }

    // MARK: - Persistence

    private var storageURL: URL {
        (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory)
            .appendingPathComponent("Logue", isDirectory: true)
            .appendingPathComponent("templates.json")
    }

    func saveToDisk() {
        let snapshot = templates
        let url = storageURL
        Task {
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try EncryptionManager.encryptCodable(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "TemplateStore")
                    .error("Failed to save templates: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearAllData() {
        templates = []
        saveToDisk()
    }

    private func loadFromDiskAsync() async {
        let url = storageURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            templates = Self.makeBuiltInTemplates()
            saveToDisk()
            isLoaded = true
            return
        }

        do {
            let loaded: [DocumentTemplate] = try await Task.detached {
                let data = try Data(contentsOf: url)
                return try EncryptionManager.decryptCodableWithFallback([DocumentTemplate].self, from: data)
            }.value

            templates = loaded

            // Ensure all built-in templates exist (new ones added in updates).
            let existingBuiltInIDs = Set(loaded.filter(\.isBuiltIn).map(\.id))
            let missing = Self.makeBuiltInTemplates().filter { !existingBuiltInIDs.contains($0.id) }
            if !missing.isEmpty {
                templates.append(contentsOf: missing)
                saveToDisk()
            }

            isLoaded = true
        } catch {
            logger.error("Failed to load templates: \(error.localizedDescription, privacy: .public)")
            templates = Self.makeBuiltInTemplates()
            saveToDisk()
            isLoaded = true
        }
    }
}
