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
        /// Carried through because a document has somewhere to put them, and because the same
        /// file dropped straight into the storage folder keeps its tags — the two paths
        /// disagreeing on one file is worse than either rule on its own.
        let tags: [String]
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

        var tags: [String] = []
        if let frontmatter = parseFrontmatter(body) {
            body = frontmatter.remainder
            title = frontmatter.title
            tags = frontmatter.tags
        }
        // The heading is read whatever the frontmatter said, so a note carrying both
        // — the common Obsidian shape — does not open with its title twice. It only
        // supplies the title when the frontmatter did not, and is only removed when
        // it is the title, so an unrelated first heading stays part of the document.
        if let heading = parseLeadingHeading(body) {
            if title == nil {
                body = heading.remainder
                title = heading.title
            } else if matchesTitle(heading.title, title) {
                body = heading.remainder
            }
        }

        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (fileName as NSString).deletingPathExtension
        let resolved = sanitisedTitle(title ?? fallback, fallback: fallback)

        return ImportedDocument(
            title: resolved.isEmpty ? "Imported Note" : resolved,
            body: body,
            tags: tags
        )
    }

    // MARK: - Title Sources

    /// A minimal YAML frontmatter reader: a `---` fence on the first line, a closing
    /// fence, and the `title:` and `tags:` keys between them. Anything else in the block is
    /// dropped with it, because keeping the raw block would show YAML to the user as prose.
    ///
    /// Returns `nil` unless the block actually looks like YAML. A markdown file may
    /// open with a `---` thematic break, and treating that as a fence would discard
    /// every paragraph up to the next one — silent, unrecoverable content loss.
    private static func parseFrontmatter(_ text: String) -> (title: String?, tags: [String], remainder: String)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        })
        else { return nil }

        let block = lines[1 ..< closing]
        guard block.allSatisfy(isYAMLLine) else { return nil }

        var title: String?
        for line in block where line.first?.isWhitespace != true {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("title:") else { continue }
            let value = unquoted(String(trimmed.dropFirst("title:".count))
                .trimmingCharacters(in: .whitespaces))
            // Keep looking when the key carries no value, so a later `title:` that
            // does have one still wins.
            if !value.isEmpty {
                title = value
                break
            }
        }
        let remainder = lines[(closing + 1)...].joined(separator: "\n")
        return (title, parsedTags(in: block), remainder)
    }

    /// Tags written either inline (`tags: [a, b]`) or as a YAML sequence beneath the key.
    private static func parsedTags(in block: ArraySlice<String>) -> [String] {
        var collecting = false
        var tags: [String] = []
        for line in block {
            let indented = line.first?.isWhitespace == true
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if collecting, indented, trimmed.hasPrefix("- ") {
                tags.append(cleanedTag(String(trimmed.dropFirst(2))))
                continue
            }
            collecting = false
            guard !indented, trimmed.lowercased().hasPrefix("tags:") else { continue }
            let inline = String(trimmed.dropFirst("tags:".count)).trimmingCharacters(in: .whitespaces)
            if inline.hasPrefix("["), inline.hasSuffix("]") {
                tags += inline.dropFirst().dropLast().split(separator: ",").map { cleanedTag(String($0)) }
            } else if inline.isEmpty {
                collecting = true
            } else {
                tags.append(cleanedTag(inline))
            }
        }
        return tags.filter { !$0.isEmpty }
    }

    private static func cleanedTag(_ raw: String) -> String {
        unquoted(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Whether a line inside a fence is plausibly YAML: blank, a comment, a
    /// `key:` mapping, or a `- ` sequence item. Prose fails all four.
    private static func isYAMLLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") {
            return true
        }
        guard let colon = trimmed.firstIndex(of: ":") else { return false }
        let key = trimmed[trimmed.startIndex ..< colon]
        return !key.isEmpty && !key.contains(" ")
    }

    /// Strips one matching pair of surrounding quotes. Trimming each end
    /// independently would turn `"Q1" review` into an unbalanced `Q1" review`.
    private static func unquoted(_ value: String) -> String {
        for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Whether a heading says the same thing as the title, ignoring case and
    /// surrounding whitespace — enough to spot a duplicate without discarding a
    /// heading that merely resembles one.
    private static func matchesTitle(_ heading: String, _ title: String?) -> Bool {
        guard let title else { return false }
        return heading.compare(
            title,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
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
    ///
    /// Filters scalars rather than characters, and on category `Cc` rather than
    /// `CharacterSet.controlCharacters`, which also covers `Cf`. Judging a whole
    /// grapheme by its scalars deleted any emoji built with a zero-width joiner —
    /// `👩‍💻` vanished, and a title that was only `👨‍👩‍👧‍👦` was lost entirely.
    private static func sanitisedTitle(_ raw: String, fallback: String) -> String {
        // `Cc` already covers newlines and tabs; the separators do not fall under it.
        let stripped: Set<Unicode.GeneralCategory> = [.control, .lineSeparator, .paragraphSeparator]
        let scalars = raw.unicodeScalars.filter { !stripped.contains($0.properties.generalCategory) }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty, raw != fallback {
            return sanitisedTitle(fallback, fallback: fallback)
        }
        return String(cleaned.prefix(maxTitleLength))
    }
}
