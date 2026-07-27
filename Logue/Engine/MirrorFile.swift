import Foundation

/// Converts a document to and from its plain-markdown mirror file.
///
/// The encrypted store remains the source of truth. A mirror exists so git, other
/// editors, and AI agents can see and edit documents as ordinary files — so every
/// file carries its document's identifier, letting an external edit be applied back
/// to the right document even if the file has been renamed or moved.
///
/// Applying an edit is deliberately conservative: a file whose identifier is missing
/// or does not match is **refused** rather than merged, because guessing which
/// document a stray file belongs to risks overwriting the wrong one.
enum MirrorFile {
    /// Frontmatter key holding the document identifier.
    ///
    /// Underscore-prefixed to mark it as app-owned: `PropertyKey.sanitisedKey` refuses
    /// such names, so a user cannot create a property that collides with it.
    static let identifierKey = "_logue_id"

    // MARK: - Rendering

    /// Renders the document as a markdown file with YAML frontmatter.
    ///
    /// Field order is fixed and lists are sorted where order carries no meaning, so
    /// the same document always renders to identical bytes — these files are
    /// git-tracked and unstable output would mean a diff on every save.
    static func render(_ document: WritingDocument) -> String {
        var fields: [(key: String, value: FrontmatterValue)] = [
            (identifierKey, .scalar(document.id.uuidString)),
            ("title", .scalar(document.title)),
        ]

        // Properties, key-sorted for stability.
        for key in document.propertyKeys {
            guard let value = document.property(key) else { continue }
            fields.append((key, frontmatterValue(for: value)))
        }

        // Relationships in a fixed kind order, targets as wikilinks.
        for kind in RelationshipKind.allCases {
            guard let targets = document.typedRelationships[kind], !targets.isEmpty else { continue }
            fields.append((kind.key, .list(targets.map(asWikiLink))))
        }

        if !document.tags.isEmpty {
            fields.append(("tags", .list(document.tags)))
        }

        // Always append exactly one newline, and `applying` always strips exactly one.
        // Appending only when missing would not be reversible: both "x" and "x\n"
        // would render identically, so an external edit could not tell them apart and
        // round-tripping would quietly alter the body.
        return MarkdownFrontmatter.render(fields) + document.body + "\n"
    }

    // MARK: - Identifying

    /// The document identifier a mirror file claims, if any.
    static func identifier(in markdown: String) -> UUID? {
        guard case let .scalar(raw)? = MarkdownFrontmatter.parse(markdown).fields[identifierKey]
        else { return nil }
        return UUID(uuidString: raw)
    }

    // MARK: - Applying

    /// Applies an externally edited file back onto `document`.
    ///
    /// Returns `nil` when the file does not identify itself as this document, so a
    /// mismatched or unidentified file can never overwrite one.
    ///
    /// Only fields present in the file are applied. A file that omits a key leaves
    /// that value untouched rather than clearing it, so an agent or editor writing a
    /// partial file cannot silently drop metadata.
    static func applying(_ markdown: String, to document: WritingDocument) -> WritingDocument? {
        guard let identifier = identifier(in: markdown), identifier == document.id else { return nil }

        let parsed = MarkdownFrontmatter.parse(markdown)
        var updated = document

        // Strips the single newline `render` appends, so render → apply is exact.
        updated.body = parsed.body.hasSuffix("\n")
            ? String(parsed.body.dropLast())
            : parsed.body

        if case let .scalar(title)? = parsed.fields["title"],
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            updated.title = title
        }

        if case let .list(tags)? = parsed.fields["tags"] {
            updated.tags = tags
        }

        for kind in RelationshipKind.allCases {
            guard case let .list(targets)? = parsed.fields[kind.key] else { continue }
            updated.setRelationship(kind, targets: targets.map(strippingWikiLink))
        }

        // Remaining scalar keys become properties, skipping the app-owned and
        // already-handled ones.
        let reserved = Set([identifierKey, "title", "tags"] + RelationshipKind.allCases.map(\.key))
        for (key, value) in parsed.fields where !reserved.contains(key) {
            guard case let .scalar(raw) = value else { continue }
            updated.setProperty(key, value: .text(raw))
        }

        updated.modifiedAt = Date()
        return updated
    }

    /// Whether a file differs from what the document would currently render to.
    ///
    /// Used to skip no-op writes and to detect genuine external edits. Compares
    /// rendered output rather than field-by-field, so it cannot disagree with `render`.
    static func hasChanges(_ markdown: String, comparedTo document: WritingDocument) -> Bool {
        normalised(markdown) != normalised(render(document))
    }

    // MARK: - Private

    private static func frontmatterValue(for value: PropertyValue) -> FrontmatterValue {
        switch value {
        case let .list(items): .list(items)
        default: .scalar(value.displayString)
        }
    }

    /// Relationship targets are stored bare but written as wikilinks, so the file
    /// reads like the rest of the markdown and other tools recognise the reference.
    private static func asWikiLink(_ target: String) -> String {
        target.hasPrefix("[[") ? target : "[[\(target)]]"
    }

    private static func strippingWikiLink(_ raw: String) -> String {
        WikiLinkParser.links(in: raw).first?.target ?? raw
    }

    private static func normalised(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "\r\n", with: "\n")
    }
}
