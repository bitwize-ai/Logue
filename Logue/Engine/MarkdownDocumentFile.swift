import Foundation

/// The plain-markdown storage format for a document.
///
/// The file **is** the document, so round-trip fidelity is the whole contract: anything
/// a document holds must survive a write and a read. Where that is impossible the field
/// belongs in `DocumentDerived` instead, stored encrypted.
///
/// Reading is deliberately tolerant, because these files are meant to be hand-edited:
/// an unrecognised key becomes a property rather than being dropped, and a malformed
/// date falls back instead of failing the whole read. The one strict requirement is the
/// identifier — without it the file is not a known document, and inventing one risks
/// attaching it to the wrong record.
enum MarkdownDocumentFile {
    /// Frontmatter key holding the document identifier.
    ///
    /// Underscore-prefixed to mark it app-owned: `PropertyKey.sanitisedKey` refuses such
    /// names, so a user cannot create a property that collides with it.
    static let identifierKey = "_logue_id"

    /// Keys the format owns. Anything else in frontmatter is treated as a property.
    private static var reservedKeys: Set<String> {
        Set(
            [identifierKey, "title", "tags", "created", "icon", "width", "pinned", "organised"]
                + RelationshipKind.allCases.map(\.key)
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Writing

    /// Renders content as a markdown file.
    ///
    /// Key order is fixed and lists are emitted in a stable order, so the same document
    /// always produces identical bytes — these files may be tracked in git, and unstable
    /// output would mean a diff on every save.
    static func render(_ content: DocumentContent) -> String {
        var fields: [(key: String, value: FrontmatterValue)] = [
            (identifierKey, .scalar(content.id.uuidString)),
            ("title", .scalar(content.title)),
            ("created", .scalar(isoFormatter.string(from: content.createdAt))),
        ]

        if let icon = content.icon {
            fields.append(("icon", .scalar(icon)))
        }
        if let width = content.storedWidthMode {
            fields.append(("width", .scalar(width.rawValue)))
        }
        if content.isPinned {
            fields.append(("pinned", .scalar("true")))
        }
        if let organised = content.storedIsOrganised {
            fields.append(("organised", .scalar(organised ? "true" : "false")))
        }

        // Properties, key-sorted for stability.
        for key in (content.properties ?? [:]).keys.sorted() {
            guard let value = content.properties?[key] else { continue }
            switch value {
            case let .list(items): fields.append((key, .list(items)))
            default: fields.append((key, .scalar(value.displayString)))
            }
        }

        // Relationships in a fixed kind order, targets as wikilinks so the file reads
        // like the rest of the markdown.
        for kind in RelationshipKind.allCases {
            guard let targets = content.relationships?[kind.key], !targets.isEmpty else { continue }
            fields.append((kind.key, .list(targets.map(asWikiLink))))
        }

        if !content.tags.isEmpty {
            fields.append(("tags", .list(content.tags)))
        }

        // Exactly one trailing newline is appended and exactly one is stripped on read,
        // so the round trip is reversible. Appending only when absent would make "x" and
        // "x\n" render identically.
        return MarkdownFrontmatter.render(fields) + content.body + "\n"
    }

    // MARK: - Reading

    /// The document identifier a file claims, without a full parse.
    static func identifier(in markdown: String) -> UUID? {
        guard case let .scalar(raw)? = MarkdownFrontmatter.parse(markdown).fields[identifierKey]
        else { return nil }
        return UUID(uuidString: raw)
    }

    /// Reads content from a file, or `nil` when it carries no identifier.
    static func content(from markdown: String) -> DocumentContent? {
        guard let id = identifier(in: markdown) else { return nil }

        let parsed = MarkdownFrontmatter.parse(markdown)
        var content = WritingDocument().content
        content.id = id

        content.body = parsed.body.hasSuffix("\n")
            ? String(parsed.body.dropLast())
            : parsed.body

        if case let .scalar(title)? = parsed.fields["title"] {
            content.title = title
        }
        if case let .list(tags)? = parsed.fields["tags"] {
            content.tags = tags
        }
        if case let .scalar(icon)? = parsed.fields["icon"] {
            content.icon = DocumentIcon.sanitised(icon)
        }
        if case let .scalar(width)? = parsed.fields["width"] {
            content.storedWidthMode = DocumentWidthMode(rawValue: width)
        }
        if case let .scalar(pinned)? = parsed.fields["pinned"] {
            content.isPinned = pinned == "true"
        }
        if case let .scalar(organised)? = parsed.fields["organised"] {
            content.storedIsOrganised = organised == "true"
        }
        // A malformed date falls back to the default rather than failing the read: a
        // wrong timestamp is recoverable, an unreadable document is not.
        if case let .scalar(created)? = parsed.fields["created"],
           let date = isoFormatter.date(from: created)
        {
            content.createdAt = date
        }

        var relationships: [String: [String]] = [:]
        for kind in RelationshipKind.allCases {
            guard case let .list(targets)? = parsed.fields[kind.key] else { continue }
            relationships[kind.key] = targets.map(strippingWikiLink)
        }
        content.relationships = relationships.isEmpty ? nil : relationships

        // Everything unrecognised becomes a property, so hand-added frontmatter is kept
        // rather than silently discarded on the next write.
        var properties: [String: PropertyValue] = [:]
        for (key, value) in parsed.fields where !reservedKeys.contains(key) {
            switch value {
            case let .scalar(raw): properties[key] = .text(raw)
            case let .list(items): properties[key] = .list(items)
            }
        }
        content.properties = properties.isEmpty ? nil : properties

        return content
    }

    // MARK: - Private

    private static func asWikiLink(_ target: String) -> String {
        target.hasPrefix("[[") ? target : "[[\(target)]]"
    }

    private static func strippingWikiLink(_ raw: String) -> String {
        WikiLinkParser.links(in: raw).first?.target ?? raw
    }
}
