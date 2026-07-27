import Foundation

/// What to do with a markdown file found in the mirror folder.
///
/// Separated from the file I/O so the rules — especially the refusal to resurrect a
/// deleted document — are testable without touching disk or the stores.
enum MirrorImportPlan: Equatable, Sendable {
    /// Already represented by a document; the normal sync path handles it.
    case existing(documentID: UUID)
    /// Carries an identifier no document has. Left alone.
    case ignoreUnknownIdentifier(UUID)
    /// Never seen before; becomes a new document.
    case importAsNew(title: String, body: String, tags: [String])

    /// Decides what a file represents.
    ///
    /// A file with an identifier that matches nothing is **ignored** rather than
    /// imported. The likeliest cause is a document deleted in the app while its mirror
    /// file remained, and silently bringing it back would undo a deliberate deletion.
    /// The cost is an orphan file that stays on disk until removed by hand.
    static func plan(
        fileContents: String,
        filename: String,
        knownDocumentIDs: Set<UUID>
    ) -> MirrorImportPlan {
        if let identifier = MirrorFile.identifier(in: fileContents) {
            return knownDocumentIDs.contains(identifier)
                ? .existing(documentID: identifier)
                : .ignoreUnknownIdentifier(identifier)
        }

        let parsed = MarkdownFrontmatter.parse(fileContents)
        var tags: [String] = []
        if case let .list(parsedTags) = parsed.fields["tags"] ?? .list([]) {
            tags = parsedTags
        }

        return .importAsNew(
            title: title(from: parsed.fields, filename: filename),
            body: parsed.body,
            tags: tags
        )
    }

    /// Prefers an explicit `title:`, falling back to the filename without extension.
    private static func title(from fields: [String: FrontmatterValue], filename: String) -> String {
        if case let .scalar(explicit)? = fields["title"],
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return explicit
        }

        let stem = (filename as NSString).deletingPathExtension
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Document" : trimmed
    }
}
