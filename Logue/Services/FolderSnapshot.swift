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

    /// The files that are not `_space.md`.
    var documentFiles: [URL] {
        files.filter { !SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
    }

    /// The `_space.md` files.
    var spaceFiles: [URL] {
        files.filter { SpaceFile.isSpaceFile(filename: $0.lastPathComponent) }
    }
}
