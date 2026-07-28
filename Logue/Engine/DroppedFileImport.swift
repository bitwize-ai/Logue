import Foundation

/// What a markdown file that carries no Logue identifier should become.
///
/// A file dropped into the folder by hand has no frontmatter to read a title from, so the
/// filename stands in — which is what a person would expect, having just named it.
///
/// Deciding whether a file is *already* a document is deliberately not here: that is
/// `ExternalChangePlanner`'s job, and having it in two places is how the two answers drift apart.
enum DroppedFileImport {
    struct Fields: Equatable, Sendable {
        let title: String
        let body: String
        let tags: [String]
    }

    /// Reads a file that has no identifier. Returns `nil` if it turns out to have one, so a real
    /// document can never be adopted a second time under a new identity.
    static func fields(fileContents: String, filename: String) -> Fields? {
        guard MarkdownDocumentFile.identifier(in: fileContents) == nil else { return nil }

        let parsed = MarkdownFrontmatter.parse(fileContents)
        var tags: [String] = []
        switch parsed.fields["tags"] {
        case let .list(parsedTags):
            tags = parsedTags
        case let .scalar(single):
            // A single tag is legitimately written `tags: work`. Reading only `.list` dropped it.
            tags = [single].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case nil:
            break
        }

        // The same heading rule as `MarkdownImport`, and for the same reason it exists there: a
        // note whose first line is `# Title` should not open with its title repeated as body text.
        // The two paths giving one file two different titles is the failure this type's own
        // documentation warns about, and they did — menu import promoted the heading, dropping the
        // file into the folder left it in the body.
        let explicit = explicitTitle(in: parsed.fields)
        var body = parsed.body
        var title = explicit

        if let heading = leadingHeading(in: body) {
            if explicit == nil {
                title = heading.title
                body = heading.remainder
            } else if heading.title.compare(explicit ?? "", options: [.caseInsensitive]) == .orderedSame {
                body = heading.remainder
            }
        }

        return Fields(
            title: title ?? filenameTitle(filename),
            body: body,
            tags: tags
        )
    }

    /// Uses a `# Heading` as the title when it is the first non-empty line.
    private static func leadingHeading(in text: String) -> (title: String, remainder: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        else { return nil }

        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("# ") else { return nil }
        let heading = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !heading.isEmpty else { return nil }

        return (heading, lines[(index + 1)...].joined(separator: "\n"))
    }

    private static func explicitTitle(in fields: [String: FrontmatterValue]) -> String? {
        guard case let .scalar(explicit)? = fields["title"],
              !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return explicit
    }

    /// The filename without its extension, for a file that names itself no other way.
    private static func filenameTitle(_ filename: String) -> String {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)

        // A name that is nothing but an extension — ".md" — has no stem to use. Foundation reads
        // it as a hidden file rather than an empty name, so `deletingPathExtension` hands it
        // straight back and the title would end up being the extension.
        let isBareExtension = name.hasPrefix(".") && !name.dropFirst().contains(".")
        let stem = isBareExtension
            ? ""
            : (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)

        return stem.isEmpty ? "Untitled Document" : stem
    }
}
