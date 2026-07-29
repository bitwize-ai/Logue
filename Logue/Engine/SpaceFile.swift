import Foundation

/// The `_space.md` file that gives a folder its space identity.
///
/// Without it, renaming a folder is indistinguishable from deleting one and creating
/// another, so the space would be recreated and lose its icon, colour and order.
///
/// Visible rather than a hidden dotfile, deliberately: someone who breaks hidden state
/// has no way to learn why their space changed. The file explains itself in a comment so
/// the reason is where the reader is.
///
/// **The identity is marked, not protected.** Nothing prevents an editor from changing
/// it. If it is altered or removed the folder simply reads as a new space — clearly
/// degraded, never corrupted.
enum SpaceFile {
    static let filename = "_space.md"
    static let identifierKey = "_logue_space_id"
    static let managedKey = "_logue_managed"

    /// What a `_space.md` says about its folder.
    struct Identity: Equatable, Sendable {
        let id: UUID
        let icon: String?
        let color: String?
        let sortOrder: Int
    }

    private static let note = """
    <!-- Managed by Logue. The `_logue_*` values identify this folder as a space —
         editing or removing them makes Logue treat this as a brand-new space and
         lose its icon, colour and order. The rest of this file is yours. -->
    """

    // MARK: - Writing

    /// Renders a space file, keeping any prose the user added below the managed note.
    ///
    /// The file says "The rest of this file is yours" and the design promised the body would be
    /// preserved. It was not: every save rewrote the file from scratch, so anything written there was
    /// destroyed by the next keystroke in that space.
    static func render(_ space: Space, keepingBodyOf existing: String?) -> String {
        let rendered = render(space)
        guard let existing, let kept = userBody(of: existing) else { return rendered }
        return rendered + "\n" + kept + "\n"
    }

    /// Whatever follows the managed note, if it is not just whitespace.
    private static func userBody(of markdown: String) -> String? {
        let body = MarkdownFrontmatter.parse(markdown).body
        guard let noteEnd = body.range(of: note)?.upperBound else {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let trimmed = body[noteEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func render(_ space: Space) -> String {
        var fields: [(key: String, value: FrontmatterValue)] = [
            (identifierKey, .scalar(space.id.uuidString)),
            (managedKey, .scalar("true")),
        ]
        if let icon = space.icon {
            fields.append(("icon", .scalar(icon)))
        }
        if let color = space.color {
            fields.append(("color", .scalar(color)))
        }
        fields.append(("order", .scalar(String(space.sortOrder))))

        return MarkdownFrontmatter.render(fields) + note + "\n"
    }

    // MARK: - Reading

    static func identity(from markdown: String) -> Identity? {
        let parsed = MarkdownFrontmatter.parse(markdown)

        guard case let .scalar(raw)? = parsed.fields[identifierKey],
              let id = UUID(uuidString: raw)
        else { return nil }

        var icon: String?
        if case let .scalar(value)? = parsed.fields["icon"] {
            icon = value
        }
        var color: String?
        if case let .scalar(value)? = parsed.fields["color"] {
            color = value
        }
        // A missing or unparseable order falls back rather than failing the read.
        var sortOrder = 0
        if case let .scalar(value)? = parsed.fields["order"], let parsedOrder = Int(value) {
            sortOrder = parsedOrder
        }

        return Identity(id: id, icon: icon, color: color, sortOrder: sortOrder)
    }

    // MARK: - Recognition

    /// Whether a filename is the space file. Checked so it is never imported as a
    /// document.
    static func isSpaceFile(filename: String) -> Bool {
        filename.caseInsensitiveCompare(Self.filename) == .orderedSame
    }

    /// Whether contents carry a space identity — a second check, in case the file was
    /// renamed.
    static func isSpaceFile(contents: String) -> Bool {
        MarkdownFrontmatter.parse(contents).fields[identifierKey] != nil
    }
}
