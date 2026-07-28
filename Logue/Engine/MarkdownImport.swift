import Foundation

/// Turns the contents of a markdown or plain-text file into a document title and body.
///
/// Everything here is pure string work so it can be tested without a store or a
/// filesystem. Reading files and creating documents live in `DocumentStore+Import`.
enum MarkdownImport {
    /// File extensions the importer accepts, lowercase.
    static let allowedExtensions: Set<String> = ["md", "markdown", "txt"]

    /// Files larger than this are refused — a multi-megabyte "note" is almost
    /// certainly not prose, and the block editor re-parses the whole body on edit.
    static let maxFileBytes = 2 * 1024 * 1024

    /// Titles are capped well below any storage limit because they are embedded in
    /// LLM prompts (search, suggestions, chat context) alongside other titles.
    static let maxTitleLength = 120

    struct ImportedDocument: Equatable {
        let title: String
        let body: String
    }

    enum ImportError: Error, Equatable {
        case emptyFile
        case unsupportedExtension(String)
        case fileTooLarge(bytes: Int)
    }

    /// Derives a document from a file's name and contents.
    ///
    /// Title precedence: YAML frontmatter `title:` → leading `# ` heading → filename.
    /// Whichever source supplies the title is removed from the body so the imported
    /// document does not open with its own title duplicated as the first line.
    static func document(fileName: String, contents rawContents: String) throws -> ImportedDocument {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw ImportError.unsupportedExtension(ext)
        }
        guard rawContents.utf8.count <= maxFileBytes else {
            throw ImportError.fileTooLarge(bytes: rawContents.utf8.count)
        }
        // Normalise line endings first and parse only the result. `CharacterSet
        // .whitespaces` is Zs plus tab — it does not contain `\r` — so a Windows
        // file would otherwise fail every `== "---"` comparison and show its raw
        // YAML block as prose. Normalising also keeps `\r` out of the stored body.
        let contents = rawContents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Nothing to import. Checked against the raw contents rather than the
        // parsed body, so a heading-only file still imports as a titled note.
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        var body = contents
        var title: String?

        if let frontmatter = parseFrontmatter(body) {
            body = frontmatter.remainder
            title = frontmatter.title
        }
        if title == nil, let heading = parseLeadingHeading(body) {
            body = heading.remainder
            title = heading.title
        }

        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (fileName as NSString).deletingPathExtension
        let resolved = sanitisedTitle(title ?? fallback, fallback: fallback)

        return ImportedDocument(title: resolved.isEmpty ? "Imported Note" : resolved, body: body)
    }

    // MARK: - Title Sources

    /// A minimal YAML frontmatter reader: a `---` fence on the first line, a closing
    /// fence, and an optional `title:` key between them. Anything more exotic in the
    /// block (tags, dates) is simply dropped with it — those keys have no home in a
    /// `WritingDocument`, and keeping the raw block would show YAML as prose.
    private static func parseFrontmatter(_ text: String) -> (title: String?, remainder: String)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        })
        else { return nil }

        var title: String?
        for line in lines[1 ..< closing] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("title:") else { continue }
            let value = trimmed.dropFirst("title:".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                title = value
            }
            break
        }
        let remainder = lines[(closing + 1)...].joined(separator: "\n")
        return (title, remainder)
    }

    /// Uses a `# Heading` as the title when it is the first non-empty line.
    private static func parseLeadingHeading(_ text: String) -> (title: String, remainder: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        else { return nil }

        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("# ") else { return nil }
        let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let remainder = lines[(index + 1)...].joined(separator: "\n")
        return (title, remainder)
    }

    /// Collapses a candidate title to a single safe line: control characters and
    /// newlines stripped, whitespace trimmed, length capped. Falls back when the
    /// result is empty (e.g. a filename that was all symbols).
    private static func sanitisedTitle(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty, raw != fallback {
            return sanitisedTitle(fallback, fallback: fallback)
        }
        return String(cleaned.prefix(maxTitleLength))
    }
}
