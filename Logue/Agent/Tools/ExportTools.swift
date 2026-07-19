import Foundation
import MLXLMCommon
import os.log

// MARK: - ExportDocumentPDFTool

/// Exports a document to PDF and writes it to disk.
///
/// Destination safety: the agent may only write under the user's Documents or Downloads
/// directory. Attempts to write elsewhere (e.g. `/etc/…`, `..` traversal, symlinks that
/// resolve outside those roots) are rejected with a clear error.
struct ExportDocumentPDFTool: AgentTool {
    let name = "export_document_pdf"
    let description = """
    Export a document to PDF and save it to disk. Defaults to ~/Documents/Logue Exports/ \
    if no destination is given. The destination must be under the user's Documents or Downloads folder.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "documentID": AgentToolSpec.stringParam("UUID of the document to export"),
                "destinationFolder": AgentToolSpec.stringParam(
                    "Absolute path to the folder where the PDF will be written (optional)."
                ),
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

        let requestedDest: URL = if let rawDest = arguments["destinationFolder"] as? String, !rawDest.isEmpty {
            try resolveAndValidate(destinationFolder: rawDest)
        } else {
            URL.homeDirectory
                .appending(path: "Documents", directoryHint: .isDirectory)
                .appending(path: "Logue Exports", directoryHint: .isDirectory)
        }

        // Fetch doc + render on main actor
        let (doc, pdfData) = try await MainActor.run { () -> (WritingDocument, NSData) in
            guard let doc = DocumentStore.shared.documents.first(where: { $0.id == documentID }) else {
                throw AgentToolError.documentNotFound(idString)
            }
            guard let data = PDFExportService.renderPDFData(document: doc) else {
                throw AgentToolError.executionFailed("PDF renderer returned no data")
            }
            return (doc, data)
        }

        // Create destination folder if needed
        do {
            try FileManager.default.createDirectory(at: requestedDest, withIntermediateDirectories: true)
        } catch {
            throw AgentToolError.executionFailed(
                "Could not create destination folder: \(error.localizedDescription)"
            )
        }

        // Dedupe filename
        let safeTitle = doc.title
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .replacingOccurrences(of: "/", with: "-")
        let baseName = safeTitle.isEmpty ? "document" : safeTitle
        var fileURL = requestedDest.appending(path: "\(baseName).pdf")
        var suffix = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            suffix += 1
            fileURL = requestedDest.appending(path: "\(baseName) (\(suffix)).pdf")
        }

        do {
            try pdfData.write(to: fileURL, options: .atomic)
        } catch {
            throw AgentToolError.executionFailed(
                "Could not write PDF: \(error.localizedDescription)"
            )
        }

        return "Exported \"\(doc.title)\" to \(fileURL.path)"
    }

    // MARK: - Path Validation

    /// Resolves the destination to an absolute URL and verifies it's under the user's
    /// Documents or Downloads tree — no `..` traversal, no symlink breakouts.
    private func resolveAndValidate(destinationFolder raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Reject obvious traversal markers
        if trimmed.contains("..") {
            throw AgentToolError.invalidParameter("destinationFolder", "Path traversal is not allowed")
        }

        // Expand tilde and resolve to absolute URL
        let expanded = (trimmed as NSString).expandingTildeInPath
        let candidate = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        // Allowed roots
        let docsRoot = URL.homeDirectory.appending(path: "Documents").standardizedFileURL
            .resolvingSymlinksInPath()
        let downloadsRoot = URL.homeDirectory.appending(path: "Downloads").standardizedFileURL
            .resolvingSymlinksInPath()

        let allowed = [docsRoot, downloadsRoot].contains { root in
            isSubpath(candidate, of: root)
        }
        guard allowed else {
            throw AgentToolError.invalidParameter(
                "destinationFolder",
                "Must be inside ~/Documents or ~/Downloads"
            )
        }
        return candidate
    }

    private func isSubpath(_ child: URL, of root: URL) -> Bool {
        let childComponents = child.pathComponents
        let rootComponents = root.pathComponents
        guard childComponents.count >= rootComponents.count else { return false }
        return Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }
}
