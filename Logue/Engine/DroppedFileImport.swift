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
        if case let .list(parsedTags) = parsed.fields["tags"] ?? .list([]) {
            tags = parsedTags
        }

        return Fields(
            title: title(from: parsed.fields, filename: filename),
            body: parsed.body,
            tags: tags
        )
    }

    /// Prefers an explicit `title:`, falling back to the filename without its extension.
    private static func title(from fields: [String: FrontmatterValue], filename: String) -> String {
        if case let .scalar(explicit)? = fields["title"],
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return explicit
        }

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
