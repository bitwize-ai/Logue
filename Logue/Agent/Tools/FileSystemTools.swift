import Foundation
import MLXLMCommon
import PDFKit

// MARK: - Constants

private enum FileToolLimits {
    /// Cap the listed file count so a malformed `~/` listing doesn't
    /// flood the conversation with thousands of paths.
    static let maxListedEntries = 200
    /// Cap extracted text from `read_file_at_path` so a 500-page PDF
    /// doesn't blow the context window. Sidekick uses ~120 KB; we match.
    static let maxExtractedChars = 120_000
}

// MARK: - ListDirectoryTool

/// Phase G: lists files and folders inside a directory the user grants
/// access to. Sandbox-safe via `FileAccessGate` — the user is asked once
/// per parent folder via `NSOpenPanel`, then the bookmark persists.
struct ListDirectoryTool: AgentTool {
    let name = "list_directory"
    let description = """
    List files and folders inside a directory. Returns up to \(FileToolLimits.maxListedEntries) entries with \
    name, type (file/folder), size in bytes, and last-modified date. Use POSIX paths — \
    `~/Documents/Foo` works (tilde is expanded).
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "path": AgentToolSpec.stringParam("POSIX path of the directory (e.g. \"~/Documents\")"),
            ],
            required: ["path"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = (arguments["path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else {
            throw AgentToolError.missingParameter("path")
        }
        let url = try await MainActor.run { FileAccessGate.shared }.resolve(path: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw FileAccessGate.FileAccessError.notDirectory(path)
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let entries = urls.prefix(FileToolLimits.maxListedEntries).map { url -> [String: Any] in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            ])
            let isDirectory = values?.isDirectory ?? false
            var entry: [String: Any] = [
                "name": url.lastPathComponent,
                "path": url.path,
                "type": isDirectory ? "folder" : "file",
            ]
            if !isDirectory, let size = values?.fileSize {
                entry["size_bytes"] = size
            }
            if let modified = values?.contentModificationDate {
                entry["modified"] = ISO8601DateFormatter().string(from: modified)
            }
            return entry
        }
        let payload: [String: Any] = [
            "directory": url.path,
            "entry_count": entries.count,
            "truncated": urls.count > FileToolLimits.maxListedEntries,
            "entries": entries,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - ReadFileAtPathTool

/// Phase G: extracts text from a file the user grants access to. Supports
/// plain text, PDF, Office (.xlsx/.docx/.pptx) via existing readers, and
/// images (the model gets a description of the file rather than the raw
/// bytes). Tilde paths are expanded.
struct ReadFileAtPathTool: AgentTool {
    let name = "read_file_at_path"
    let description = """
    Read and extract text from a file at a POSIX path. Supports plain text, PDF, Word, \
    Excel, PowerPoint, and Markdown. Image files return a placeholder note (use OCR via \
    attachment for image text). Output is capped at \(FileToolLimits.maxExtractedChars) characters.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "path": AgentToolSpec.stringParam("POSIX path of the file (e.g. \"~/Downloads/report.pdf\")"),
            ],
            required: ["path"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = (arguments["path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else {
            throw AgentToolError.missingParameter("path")
        }
        let url = try await MainActor.run { FileAccessGate.shared }.resolve(path: path)
        guard !url.hasDirectoryPath else {
            throw FileAccessGate.FileAccessError.notFile(path)
        }
        let text = try extract(from: url)
        let payload: [String: Any] = [
            "path": url.path,
            "extension": url.pathExtension,
            "char_count": text.count,
            "text": text,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func extract(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "md", "markdown", "json", "swift", "py", "js", "ts", "html", "css", "csv":
            let raw = try String(contentsOf: url, encoding: .utf8)
            return String(raw.prefix(FileToolLimits.maxExtractedChars))
        case "pdf":
            guard let pdf = PDFDocument(url: url), let raw = pdf.string else {
                return "[Could not extract text from PDF — file may be image-only or encrypted]"
            }
            return String(raw.prefix(FileToolLimits.maxExtractedChars))
        case "xlsx", "docx", "pptx":
            if let text = OfficeExtractor.extractText(from: url, maxChars: FileToolLimits.maxExtractedChars) {
                return text
            }
            return "[Could not extract text from Office document]"
        case "png", "jpg", "jpeg", "heic", "tiff", "gif":
            return "[Image file. Drag-drop into the chat to extract text via OCR.]"
        default:
            // Fall back to UTF-8 read for unknown extensions; many configs &
            // shell scripts have unusual extensions but are plain text.
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                return String(raw.prefix(FileToolLimits.maxExtractedChars))
            }
            return "[Unsupported file format: .\(ext)]"
        }
    }
}

// MARK: - WriteTextToFileTool

/// Phase G: writes plain text to a file at a POSIX path. Sidekick mirrors
/// this — they don't support modifying Office files in place either.
struct WriteTextToFileTool: AgentTool {
    let name = "write_text_to_file"
    let description = """
    Write text content to a file at a POSIX path. Creates the file if missing, replaces \
    its contents otherwise. Use for plaintext, Markdown, source code, JSON, or CSV. \
    Office formats (.xlsx/.docx/.pptx) are not modifiable in place — write a new \
    text file instead.
    """
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "path": AgentToolSpec.stringParam("POSIX path of the destination file"),
                "content": AgentToolSpec.stringParam("Text to write"),
                "append": AgentToolSpec.stringParam(
                    "If \"true\", append to the file instead of replacing. Default \"false\"."
                ),
            ],
            required: ["path", "content"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = (arguments["path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else {
            throw AgentToolError.missingParameter("path")
        }
        guard let content = arguments["content"] as? String else {
            throw AgentToolError.missingParameter("content")
        }
        let appendFlag = (arguments["append"] as? String)?.lowercased() == "true"

        // Resolve the parent dir (the file may not exist yet — we still
        // need user permission for the containing folder).
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let parent = url.deletingLastPathComponent()
        _ = try await MainActor.run { FileAccessGate.shared }.resolve(path: parent.path)

        do {
            if appendFlag, FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = content.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            throw FileAccessGate.FileAccessError.writeFailed(error.localizedDescription)
        }
        return "{\"path\":\"\(url.path)\",\"bytes_written\":\(content.utf8.count),\"appended\":\(appendFlag)}"
    }
}

// MARK: - DeleteFileAtPathTool

/// Phase G: deletes a file or empty directory. Routed through
/// `ApprovalGate` because the action is destructive.
struct DeleteFileAtPathTool: AgentTool {
    let name = "delete_file_at_path"
    let description = """
    Delete a file (or empty directory) at a POSIX path. Routed through the user-approval \
    gate — the user must confirm the deletion before it proceeds. Use sparingly.
    """
    let clearance: ToolClearance = .dangerous

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "path": AgentToolSpec.stringParam("POSIX path to delete"),
            ],
            required: ["path"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let path = (arguments["path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
        else {
            throw AgentToolError.missingParameter("path")
        }
        let url = try await MainActor.run { FileAccessGate.shared }.resolve(path: path)
        try FileManager.default.removeItem(at: url)
        return "{\"deleted\":\"\(url.path)\"}"
    }
}
