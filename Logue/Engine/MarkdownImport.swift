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
        /// The note's own last-modified date, when its frontmatter states one.
        ///
        /// Without it `modifiedAt` fell back to `createdAt`, so a note written in 2019 and edited
        /// last week imported as last modified in 2019 — with the real value visible only as a
        /// stray property.
        let modifiedAt: Date?
        /// The note's own creation date, when its frontmatter states one.
        ///
        /// Without this every imported note took `Date()`, so a 500-note vault arrived with 500
        /// timestamps within a second of each other and sorting by date was meaningless for good.
        let createdAt: Date?
        /// Frontmatter the format does not own, kept as document properties.
        ///
        /// Dropping it was the same mistake in a different place: `status:` and `project:` are not
        /// decoration on a Dataview note, they are its data. `MarkdownDocumentFile` already says an
        /// unrecognised key becomes a property rather than being dropped; this now agrees.
        let properties: [String: PropertyValue]
    }

    /// Why a file is being read, which decides how much of this is sanitising and how much is
    /// merely deriving.
    ///
    /// The distinction exists because one caller **writes the result back over the file**.
    /// `MarkdownStorageMigrator.adopt` renders what it derived and saves it, so every rule here is
    /// a rule that rewrites files in `~/Logue` — and rules written to make a foreign file safe to
    /// bring in are the wrong rules to apply to a file the user already owns and put there.
    enum Purpose {
        /// A file the user picked to bring in from elsewhere. Refused if it is too large or
        /// empty, title capped, body trimmed.
        case bringingAFileIn
        /// A file already sitting in the storage folder. The file *is* the document, so nothing
        /// is refused and nothing is reshaped — this only reads it.
        case readingAFileWeAlreadyHold

        /// Whether a file may be turned away. In the folder there is no dialog to explain a
        /// refusal, and a file that is silently un-adoptable is re-read on every scan forever.
        var refusesUnreasonableFiles: Bool {
            self == .bringingAFileIn
        }

        /// Whether the body and title may be reshaped to fit. The title cap exists because
        /// imported titles go into LLM prompts; applying it to a file the user owns truncates
        /// their text on disk with no way back.
        var reshapesContent: Bool {
            self == .bringingAFileIn
        }
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
    static func document(
        fileName: String, contents rawContents: String, purpose: Purpose = .bringingAFileIn
    ) throws -> ImportedDocument {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw ImportError.unsupportedExtension(ext)
        }
        if purpose.refusesUnreasonableFiles {
            guard rawContents.utf8.count <= maxFileBytes else {
                throw ImportError.fileTooLarge(bytes: rawContents.utf8.count)
            }
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
        if purpose.refusesUnreasonableFiles {
            guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.emptyFile
            }
        }

        var body = contents
        var title: String?
        var tags: [String] = []
        var createdAt: Date?
        var modifiedAt: Date?
        var properties: [String: PropertyValue] = [:]

        // Only when the block is plausibly YAML. `MarkdownFrontmatter.parse` takes any `---` pair
        // at the top of a file, which for a note opening with a thematic break would discard every
        // paragraph up to the next one — silent, unrecoverable content loss. That guard is the one
        // piece of frontmatter handling that stays import-specific.
        if let fenced = fencedBlock(in: body), looksLikeFrontmatter(fenced.block) {
            let parsed = MarkdownFrontmatter.parse(body)
            body = fenced.remainder

            title = scalar(parsed.fields["title"])
            tags = list(parsed.fields["tags"])
            createdAt = creationDate(in: parsed.fields)
            modifiedAt = modificationDate(in: parsed.fields)
            properties = importedProperties(from: parsed.fields, purpose: purpose)
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

        // Trimmed only for a file being brought in. For one already in the folder this rewrites
        // the user's own file, and a note opening with an indented code block came back as a
        // paragraph — the indentation is content there, not stray whitespace.
        if purpose.reshapesContent {
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fallback = (fileName as NSString).deletingPathExtension
        let resolved = sanitisedTitle(title ?? fallback, fallback: fallback, purpose: purpose)

        return ImportedDocument(
            title: resolved.isEmpty ? "Imported Note" : resolved,
            body: body,
            tags: tags,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            properties: properties
        )
    }

    // MARK: - Frontmatter

    /// The lines between a leading `---` pair, and everything after the closing one.
    ///
    /// Finding the fence is separate from parsing it because the plausibility check has to run on
    /// the block *before* anything consumes it.
    private static func fencedBlock(in text: String) -> (block: ArraySlice<String>, remainder: String)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        })
        else { return nil }

        return (lines[1 ..< closing], lines[(closing + 1)...].joined(separator: "\n"))
    }

    private static func scalar(_ value: FrontmatterValue?) -> String? {
        guard case let .scalar(text)? = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A field as a list, whichever way it was written.
    ///
    /// A single tag is legitimately written `tags: work`, which parses as a scalar. Reading only
    /// `.list` would drop it.
    private static func list(_ value: FrontmatterValue?) -> [String] {
        switch value {
        case let .list(items):
            items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case let .scalar(single):
            [single.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        case nil:
            []
        }
    }

    /// Keys naming a creation date, in the order exporters are trusted for it.
    ///
    /// `date` is last because Jekyll uses it for *publication*, which is not the same thing and is
    /// often absent from drafts.
    private static let creationKeys = ["created", "created_at", "date_created", "ctime", "date"]

    /// Keys naming a last-modified date.
    private static let modificationKeys = ["modified", "updated", "last_modified", "mtime", "date_modified"]

    private static func modificationDate(in fields: [String: FrontmatterValue]) -> Date? {
        for key in modificationKeys {
            guard let raw = scalar(fields[key]), let date = parsedDate(raw) else { continue }
            return date
        }
        return nil
    }

    private static func creationDate(in fields: [String: FrontmatterValue]) -> Date? {
        for key in creationKeys {
            guard let raw = scalar(fields[key]), let date = parsedDate(raw) else { continue }
            return date
        }
        return nil
    }

    /// Parses the date shapes note apps actually write.
    ///
    /// Deliberately a fixed list rather than a lenient `DateFormatter`: guessing wrong is worse
    /// than not knowing, because a wrong date is indistinguishable from a right one afterwards.
    /// Anything unrecognised leaves `createdAt` nil and the document takes its own creation time,
    /// which is the honest answer.
    static func parsedDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, looksLikeADate(trimmed) else { return nil }

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        if let date = isoFormatterWithFractionalSeconds.date(from: trimmed) {
            return date
        }

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd"] {
            // Built here rather than shared and mutated. `DateFormatter` is not thread-safe, and
            // this is reachable from the detached import walk — a shared instance whose
            // `dateFormat` is reassigned per call is a race waiting for a second concurrent import.
            let formatter = DateFormatter()
            // `en_US_POSIX` so a user's 24-hour or calendar settings cannot change how a file
            // parses. Local time, because a note written `2024-03-15` means that day where the
            // writer was.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    /// Whether a scalar is shaped like a date at all, before any formatter sees it.
    ///
    /// `DateFormatter` is far more permissive than its format string suggests: with `yyyy-MM-dd`
    /// it accepts `1.2.3` and returns the year 1. So `version: 1.2.3` became a date property,
    /// which `MarkdownDocumentFile` wrote back to the file as `0001-02-03T00:00:00Z` — the
    /// original string unrecoverable. And the same file already in the folder reads `1.2.3` as
    /// text, so one file got two answers depending on how it arrived.
    ///
    /// Four leading digits and a `-` or `/` separator is what every format here starts with.
    private static func looksLikeADate(_ raw: String) -> Bool {
        let leading = raw.prefix(4)
        guard leading.count == 4, leading.allSatisfy(\.isNumber) else { return false }

        guard let fifth = raw.dropFirst(4).first else { return true }
        return fifth == "-" || fifth == "/"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Frontmatter keys this importer consumes itself, so they do not also become properties.
    private static func consumedKeys(for purpose: Purpose) -> Set<String> {
        var keys = Set(["title", "tags", MarkdownDocumentFile.identifierKey] + creationKeys)
        // Only consumed where there is somewhere to put the value. `DocumentContent` has no
        // modified date, so on the adopt path consuming these deleted `modified:` from the file
        // rather than moving it — the key was taken out of properties and then dropped.
        if purpose == .bringingAFileIn {
            keys.formUnion(modificationKeys)
        }
        return keys
    }

    /// Everything else in the block, as document properties.
    ///
    /// Keys go through `PropertyKey.sanitisedKey`, which is what refuses underscore-prefixed
    /// names — so a file cannot claim an app-owned field by writing one in its frontmatter.
    private static func importedProperties(
        from fields: [String: FrontmatterValue], purpose: Purpose
    ) -> [String: PropertyValue] {
        let consumed = consumedKeys(for: purpose)
        var properties: [String: PropertyValue] = [:]
        for (rawKey, value) in fields where !consumed.contains(rawKey.lowercased()) {
            guard let key = PropertyKey.sanitisedKey(rawKey) else { continue }
            switch value {
            case let .list(items):
                let usable = items.filter { !$0.isEmpty }
                guard !usable.isEmpty else { continue }
                properties[key] = .list(usable)
            case let .scalar(raw):
                guard let typed = propertyValue(from: raw) else { continue }
                properties[key] = typed
            }
        }
        return properties
    }

    /// Types a scalar the way the user would expect to see it, rather than storing everything as
    /// text. `MarkdownDocumentFile` makes the same judgements when it reads a stored file.
    private static func propertyValue(from raw: String) -> PropertyValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "true" || trimmed == "false" {
            return .boolean(trimmed == "true")
        }
        if let date = parsedDate(trimmed) {
            return .date(date)
        }
        if trimmed.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." || $0 == "+" }),
           let number = Double(trimmed)
        {
            return .number(number)
        }
        return .text(trimmed)
    }

    /// Keys that make a `---` block frontmatter rather than prose that happens to
    /// contain a colon. Deliberately a short list of what exporters actually emit:
    /// requiring positive evidence is what stops a note opening with a horizontal
    /// rule from having its first paragraph eaten.
    private static let frontmatterKeys: Set<String> = [
        "title", "tags", "created", "updated", "date", "modified", "aliases",
        "author", "id", "_logue_id", "categories", "category", "description",
        "draft", "published", "publish", "permalink", "slug", "status", "type",
        "cssclass", "keywords", "layout",
    ]

    /// Whether every line in the block is plausibly YAML *and* at least one of them
    /// is a key an exporter would write.
    private static func looksLikeFrontmatter(_ block: ArraySlice<String>) -> Bool {
        var sawKnownKey = false
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") {
                continue
            }
            guard let key = mappingKey(in: trimmed) else { return false }
            if frontmatterKeys.contains(key) {
                sawKnownKey = true
            }
        }
        return sawKnownKey
    }

    /// The key of a `key:` or `key: value` line, lowercased, or `nil` when the line
    /// is not a mapping. The colon must end the line or be followed by whitespace,
    /// which is what separates a key from the scheme in `https://example.com`.
    private static func mappingKey(in trimmed: String) -> String? {
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let after = trimmed.index(after: colon)
        guard after == trimmed.endIndex || trimmed[after].isWhitespace else { return nil }

        let key = String(trimmed[trimmed.startIndex ..< colon])
        guard let first = key.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_",
              key.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
              })
        else { return nil }
        return key.lowercased()
    }

    /// Caps a title, breaking at a word boundary and marking that it was cut.
    ///
    /// A hard `prefix` left a title ending mid-word with nothing to say it had been shortened —
    /// a long first line of prose imported as a title that simply stopped. Falls back to a hard
    /// cut when there is no space to break on, which is what a single very long token gives.
    private static func truncated(_ title: String) -> String {
        guard title.count > maxTitleLength else { return title }

        let cut = String(title.prefix(maxTitleLength - 1))
        guard let lastSpace = cut.lastIndex(of: " "),
              cut.distance(from: cut.startIndex, to: lastSpace) > maxTitleLength / 2
        else {
            return cut + "\u{2026}"
        }
        return cut[cut.startIndex ..< lastSpace] + "\u{2026}"
    }

    /// Bidirectional overrides and isolates. `Cf` is kept as a class because that is what
    /// saves the zero-width joiner in emoji, but these particular ones let a title render
    /// reversed — "Invoice \u{202E}gpj.exe" reads as an image in the sidebar.
    private static func isBidiControl(_ scalar: Unicode.Scalar) -> Bool {
        (0x202A ... 0x202E).contains(scalar.value) || (0x2066 ... 0x2069).contains(scalar.value)
    }

    /// Whether a heading says the same thing as the title, ignoring case and
    /// surrounding whitespace — enough to spot a duplicate without discarding a
    /// heading that merely resembles one.
    private static func matchesTitle(_ heading: String, _ title: String?) -> Bool {
        guard let title else { return false }
        // Case and whitespace only. Folding diacritics too made "# Résumé" a duplicate
        // of the title "Resume" and deleted the heading.
        return heading.compare(title, options: [.caseInsensitive]) == .orderedSame
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
    private static func sanitisedTitle(
        _ raw: String, fallback: String, purpose: Purpose = .bringingAFileIn
    ) -> String {
        // `Cc` already covers newlines and tabs; the separators do not fall under it.
        let stripped: Set<Unicode.GeneralCategory> = [.control, .lineSeparator, .paragraphSeparator]
        let scalars = raw.unicodeScalars.filter {
            !stripped.contains($0.properties.generalCategory) && !isBidiControl($0)
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty, raw != fallback {
            return sanitisedTitle(fallback, fallback: fallback, purpose: purpose)
        }
        // Control characters and bidi overrides come out either way — a reversed title is a
        // spoof, and the title reaches LLM prompts on both paths. The length cap does not: it
        // would rewrite a 250-character title in the user's own file down to 115.
        return purpose.reshapesContent ? truncated(cleaned) : cleaned
    }
}
