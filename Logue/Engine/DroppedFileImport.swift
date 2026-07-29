import Foundation

/// What a markdown file that carries no Logue identifier should become.
///
/// A file dropped into the folder by hand has no identifier to read, so this decides what
/// document it becomes. It is deliberately a thin wrapper over `MarkdownImport`: this path
/// **writes its result back over the user's file**, so anything it derives differently from the
/// menu importer is not merely missing from the library, it is destroyed on disk.
///
/// That is why the whole derivation is shared rather than reimplemented. Doing it twice meant a
/// `---` block of prose was swallowed as frontmatter and deleted, a `title:` reached the document
/// unsanitised — bidi overrides and all — and `created:` plus every unrecognised key were erased
/// from the file on adoption.
///
/// Deciding whether a file is *already* a document is deliberately not here: that is
/// `ExternalChangePlanner`'s job, and having it in two places is how the two answers drift apart.
enum DroppedFileImport {
    struct Fields: Equatable, Sendable {
        let title: String
        let body: String
        let tags: [String]
        let createdAt: Date?
        let modifiedAt: Date?
        let properties: [String: PropertyValue]
    }

    /// Reads a file that has no identifier. Returns `nil` if it turns out to have one, so a real
    /// document can never be adopted a second time under a new identity — or if the file has
    /// nothing in it to adopt.
    static func fields(fileContents: String, filename: String) -> Fields? {
        guard MarkdownDocumentFile.identifier(in: fileContents) == nil else { return nil }

        do {
            let document = try MarkdownImport.document(
                fileName: usableName(filename),
                contents: fileContents,
                // This path writes its result back over the file, so it reads rather than
                // sanitises: nothing refused, nothing reshaped.
                purpose: .readingAFileWeAlreadyHold
            )
            return Fields(
                title: document.title,
                body: document.body,
                tags: document.tags,
                createdAt: document.createdAt,
                modifiedAt: document.modifiedAt,
                properties: document.properties
            )
        } catch {
            // An empty file, or one that is not a note. Adopting it would write our frontmatter
            // into something the user did not put there as a document.
            return nil
        }
    }

    /// A filename the shared derivation can work with.
    ///
    /// A name that is nothing but an extension — `.md` — has no stem to use as a title, and
    /// Foundation reads it as a hidden file rather than an empty name, so `pathExtension` is empty
    /// too. Passing it straight through meant the file was refused for having an unsupported
    /// extension, where this path used to adopt it under a placeholder title.
    private static func usableName(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBareExtension = trimmed.hasPrefix(".") && !trimmed.dropFirst().contains(".")
        guard isBareExtension || (trimmed as NSString).deletingPathExtension.isEmpty else {
            return trimmed
        }
        return "Untitled Document.md"
    }
}
