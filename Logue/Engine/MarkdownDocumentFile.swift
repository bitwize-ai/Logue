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
            [identifierKey, "title", "tags", "created", "icon", "width", "pinned", "organised", "goal"]
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
        // Written because it is part of the document: it was never emitted, so every document's
        // writing goal reset to the default on the first round trip through the folder.
        fields.append(("goal", .scalar(content.goalMode.rawValue)))

        // Properties, key-sorted for stability, each written in a form that reads back as the same
        // type. `displayString` was destroying them: `.number(5)` became `"5"` and returned as
        // `.text("5")`, `.boolean(true)` became `"Yes"`, and `.date` became a *locale-dependent*
        // medium string that cannot be parsed at all — which also broke this file's promise of
        // identical bytes for an identical document. The loss was then applied live, because
        // `ExternalChangePlanner.differs` compares properties and the next scan saw a change.
        for key in (content.properties ?? [:]).keys.sorted() {
            guard let value = content.properties?[key] else { continue }
            fields.append((key, propertyField(for: value)))
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

    /// How a property value is written so it reads back as the same type.
    ///
    /// Inference on read is the trade: a text property whose value happens to look like a number or
    /// an ISO date comes back as that type. That is worth it, because the alternative — keeping the
    /// types in a sidecar — means the file alone no longer describes the document, and someone
    /// editing a date in another editor could not.
    private static func propertyField(for value: PropertyValue) -> FrontmatterValue {
        switch value {
        case let .text(text):
            // Quoted when it would otherwise be read back as another type, so a text property
            // holding "5" stays text.
            .scalar(looksTyped(text) ? "\"\(text)\"" : text)
        case let .number(number):
            .scalar(number == number.rounded() && abs(number) < 1e15
                ? String(Int(number))
                : String(number))
        case let .date(date):
            .scalar(isoFormatter.string(from: date))
        case let .boolean(flag):
            .scalar(flag ? "true" : "false")
        case let .list(items):
            .list(items)
        case let .unknown(kind, payload):
            // Kept as its own tagged form rather than flattened: `.unknown` exists so a document
            // written by a newer build survives an older one, and flattening it here defeated that
            // in exactly the mode where the file is the only copy.
            .scalar(unknownEncoding(kind: kind, payload: payload))
        }
    }

    /// Turns a frontmatter value back into a typed property.
    private static func propertyValue(from value: FrontmatterValue) -> PropertyValue {
        switch value {
        case let .list(items):
            return .list(items)
        case let .scalar(raw):
            if let decoded = decodedUnknown(raw) {
                return decoded
            }
            if raw == "true" || raw == "false" {
                return .boolean(raw == "true")
            }
            if let number = Double(raw), looksNumeric(raw) {
                return .number(number)
            }
            if let date = isoFormatter.date(from: raw) {
                return .date(date)
            }
            return .text(raw)
        }
    }

    /// Whether a string would be read back as something other than text.
    private static func looksTyped(_ raw: String) -> Bool {
        raw == "true" || raw == "false" || looksNumeric(raw) || isoFormatter.date(from: raw) != nil
            || raw.hasPrefix(unknownPrefix)
    }

    /// Deliberately stricter than `Double(_:)`, which accepts "inf", "nan" and hex floats — none of
    /// which a user typing in a text field means as a number.
    private static func looksNumeric(_ raw: String) -> Bool {
        !raw.isEmpty && raw.allSatisfy { $0.isNumber || $0 == "-" || $0 == "." || $0 == "+" }
            && Double(raw) != nil
    }

    private static let unknownPrefix = "logue-kind:"

    private static func unknownEncoding(kind: String, payload: PreservedJSON) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else { return "\(unknownPrefix)\(kind):null" }
        return "\(unknownPrefix)\(kind):\(json)"
    }

    private static func decodedUnknown(_ raw: String) -> PropertyValue? {
        guard raw.hasPrefix(unknownPrefix) else { return nil }
        let rest = raw.dropFirst(unknownPrefix.count)
        guard let separator = rest.firstIndex(of: ":") else { return nil }

        let kind = String(rest[rest.startIndex ..< separator])
        let json = String(rest[rest.index(after: separator)...])
        let payload = (try? JSONDecoder().decode(PreservedJSON.self, from: Data(json.utf8))) ?? .null
        return .unknown(kind: kind, value: payload)
    }

    /// Reads content from a file, or `nil` when it carries no identifier.
    static func content(from markdown: String) -> DocumentContent? {
        guard let id = identifier(in: markdown) else { return nil }

        let parsed = MarkdownFrontmatter.parse(markdown)
        var content = WritingDocument().content
        content.id = id
        // `nil`, not the `false` a fresh document starts with. The invariant on this field is that
        // nil means organised — `isOrganised` is `storedIsOrganised ?? true` — so starting from
        // false and only assigning when the key is present meant every v1.0.0 document, where it is
        // nil, round-tripped to *unorganised*. Enabling markdown storage put an entire existing
        // library into the Inbox, and switching back persisted that.
        content.storedIsOrganised = nil

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
        if case let .scalar(goal)? = parsed.fields["goal"],
           let mode = WritingGoalMode(rawValue: goal)
        {
            content.goalMode = mode
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
            properties[key] = propertyValue(from: value)
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
