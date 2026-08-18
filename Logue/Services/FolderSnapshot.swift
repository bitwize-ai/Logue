import Foundation

/// One traversal of the markdown folder, read once and shared.
///
/// A scan asks the folder several different questions — which folders exist, which claim which space,
/// which files hold which document, what each document now says — and each answer used to start its
/// own traversal. That was seven walks per scan, three of them opening and decoding *every* document
/// in the library, nearly all on the main actor. On every app activation.
///
/// So the traversal became a value. Everything a scan needs is read here once, and every consumer
/// takes it as a parameter. Two consequences worth stating: the whole read can now happen in one
/// detached task, and every step of a scan sees exactly the same folder rather than a slightly newer
/// one — which also removes a class of race where an early question and a late question disagreed.
///
/// The contents are held in memory for the length of a scan. That is not new: the previous code read
/// the same bytes three times over, it just did not keep them.
struct FolderSnapshot: Sendable {
    /// Every `.md` file under the root, sorted by path.
    ///
    /// Sorted because two independent passes pick "the first file with this identifier", and a
    /// duplicated file makes that a real choice — unsorted, a save and a scan could each pick a
    /// different copy, and the loser would read as an outside edit and overwrite current text.
    let files: [URL]

    /// Every directory under the root, as components relative to it. Empty ones included: a folder
    /// someone made and has not filled yet is still a folder they made.
    let directories: [[String]]

    /// What each file said at the moment of the walk. Absent means the file could not be read.
    let contents: [URL: String]

    /// Each file's directory, as components relative to the root.
    ///
    /// Frozen here because working it out resolves symlinks, which asks the filesystem — so a consumer
    /// doing that arithmetic later was still touching the folder, and got nothing once anything moved
    /// underneath it. The snapshot is where filesystem-dependent facts belong.
    let componentsByFile: [URL: [String]]

    /// False when part of the folder could not be read.
    ///
    /// The distinction matters more than it looks: a failed traversal returns a *short list*, which is
    /// indistinguishable from an empty folder — and an empty folder used to mean "every document was
    /// deleted". A caller about to act on absence has to be able to tell the difference.
    let isComplete: Bool

    init(
        files: [URL] = [],
        directories: [[String]] = [],
        contents: [URL: String] = [:],
        componentsByFile: [URL: [String]] = [:],
        isComplete: Bool = true
    ) {
        self.files = files
        self.directories = directories
        self.contents = contents
        self.componentsByFile = componentsByFile
        self.isComplete = isComplete
    }

    /// Directories that carry the tasks marker, as components relative to the root.
    ///
    /// By marker presence rather than by name, matching the rule spaces already follow: a
    /// folder is found by its identity, never by recomputing a path from its name. So
    /// renaming `Tasks/` in Finder keeps tasks working *and* keeps them out of the document
    /// library, while a folder merely *called* `Tasks` stays an ordinary space.
    ///
    /// More than one is possible — a copied folder — and all of them are excluded. Being
    /// conservative about what counts as a document is the safe direction: the cost is a
    /// task folder that does not appear as a space, and the alternative is a user's tasks
    /// silently becoming documents.
    /// A folder that already carries a space identity is **never** a task folder, however the
    /// tasks marker got there. `Tasks` is an obvious name for a space, and users have one: if
    /// the marker won, that folder would drop out of `spaceDirectories` and `spaceFiles`, the
    /// space would read as *vanished*, and `trashDocuments(inSpace:)` would take everything in
    /// it. Space identity is older, holds documents, and misreading it destroys them —
    /// misreading a task folder as a space costs nothing.
    var taskFolders: [[String]] {
        let spaceFolders = Set(
            files
                .filter { SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
                .compactMap { componentsByFile[$0] }
                .map { $0.joined(separator: "/") }
        )

        return files.compactMap { url in
            guard TaskFile.isFolderMarker(filename: url.lastPathComponent),
                  let contents = contents[url],
                  TaskFile.markerIdentifier(in: contents) != nil,
                  let components = componentsByFile[url],
                  !spaceFolders.contains(components.joined(separator: "/"))
            else { return nil }
            return components
        }
    }

    /// Whether `components` is one of `folders` or sits inside one.
    private static func isContained(_ components: [String], in folders: [[String]]) -> Bool {
        folders.contains { folder in
            components.count >= folder.count && Array(components.prefix(folder.count)) == folder
        }
    }

    /// The files that are neither `_space.md` nor anything inside a task folder.
    var documentFiles: [URL] {
        let folders = taskFolders
        return files.filter { url in
            guard !SpaceFile.isSpaceFile(filename: url.lastPathComponent) else { return false }
            guard let components = componentsByFile[url] else { return true }
            return !Self.isContained(components, in: folders)
        }
    }

    /// The `_space.md` files, excluding any inside a task folder.
    var spaceFiles: [URL] {
        let folders = taskFolders
        return files.filter { url in
            guard SpaceFile.isSpaceFile(filename: url.lastPathComponent) else { return false }
            guard let components = componentsByFile[url] else { return true }
            return !Self.isContained(components, in: folders)
        }
    }

    /// The directories a scan may treat as spaces — everything except task folders and
    /// anything nested inside one.
    var spaceDirectories: [[String]] {
        let folders = taskFolders
        return directories.filter { !Self.isContained($0, in: folders) }
    }
}
