import Foundation
import OSLog

// MARK: - Space folders

/// Every filesystem operation on a *space's* folder, as opposed to a document's file.
///
/// Split from `MarkdownStorageMigrator` when it outgrew the project's type-size rule. The seam is the
/// one that was already there: documents and their files on one side, spaces and their folders on the
/// other, with `SpaceFolderMap` the shared idea between them.
extension MarkdownStorageMigrator {
    // MARK: - Space folders

    /// Where a space's folder is, asking the folders before the names.
    func folderURL(forSpace spaceID: UUID?, in spaces: [Space], folders: SpaceFolderMap? = nil) -> URL {
        let folders = folders ?? spaceFolderMap(in: spaces)
        return rootURL.appendingPathComponent(
            folders.components(forSpace: spaceID, in: spaces).joined(separator: "/")
        )
    }

    /// Which folder each space occupies, found by the identifier inside its `_space.md`.
    ///
    /// By identifier rather than by name, because a name can be changed on either side and the
    /// identifier cannot. It is also how a space with no folder at all is recognised — which is
    /// how a folder deleted outside the app is noticed.
    /// `spaces` only breaks ties between folders claiming the same identity — see
    /// `SpaceFolderMap.preferred`. The map is otherwise built entirely from what is on disk.
    func spaceFolderMap(in spaces: [Space] = [], using snapshot: FolderSnapshot? = nil) -> SpaceFolderMap {
        let snapshot = snapshot ?? self.snapshot()
        var candidates: [UUID: [[String]]] = [:]

        for url in snapshot.spaceFiles {
            guard let contents = snapshot.contents[url],
                  let identity = SpaceFile.identity(from: contents)
            else { continue }
            let components = directoryComponents(of: url, using: snapshot)
            guard !components.isEmpty else { continue }
            candidates[identity.id, default: []].append(components)
        }

        var index: [UUID: [String]] = [:]
        var duplicates: [[String]] = []
        var duplicateOwners: [[String]: UUID] = [:]

        for (id, paths) in candidates {
            let ordered = paths.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
            guard let winner = SpaceFolderMap.preferred(ordered, for: id, in: spaces) else { continue }
            index[id] = winner
            for loser in ordered where loser != winner {
                duplicates.append(loser)
                duplicateOwners[loser] = id
            }
        }

        return SpaceFolderMap(
            componentsByID: index,
            duplicatedFolders: duplicates.sorted { $0.joined() < $1.joined() },
            duplicateOwners: duplicateOwners
        )
    }

    /// Writes a space's identity into a folder we already know the path of.
    ///
    /// Needed when adopting a folder made outside the app: its path cannot be derived from the space
    /// name, because the name came *from* the path and may be spelled differently — `-Work` derives
    /// to `Work`. Without this the identity was never written at all, so the next scan saw a space
    /// with no folder and deleted it.
    func writeSpaceIdentity(for space: Space, atComponents components: [String]) {
        let directory = rootURL.appendingPathComponent(components.joined(separator: "/"))
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        writeIdentity(of: space, in: directory)
    }

    /// Creates a folder for every space, for the migration that turns the setting on.
    func createSpaceFolders(spaces: [Space]) {
        for space in spaces {
            do {
                try createFolder(for: space, in: spaces)
            } catch {
                // Its documents land at the root instead, which is recoverable — unlike failing
                // the migration and leaving the user with nothing.
                logger.error("Could not create a space folder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Creates a space's folder and writes its identity, for a space made in the app.
    func createFolder(for space: Space, in spaces: [Space], folders: SpaceFolderMap? = nil) throws {
        let directory = folderURL(forSpace: space.id, in: spaces, folders: folders)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeIdentity(of: space, in: directory)
    }

    /// Moves a space's folder, for a space renamed or re-parented in the app.
    ///
    /// The identity is rewritten afterwards so the moved folder still names its space.
    func moveFolder(from components: [String], for space: Space, in spaces: [Space]) throws {
        let source = rootURL.appendingPathComponent(components.joined(separator: "/"))
        // The destination is name-derived on purpose: renaming a space is precisely the act of
        // asking for a folder named after the new name, so the folder map must not answer with
        // where the folder currently is.
        let destination = rootURL.appendingPathComponent(
            SpaceFolderLayout.directoryComponents(forSpace: space.id, in: spaces).joined(separator: "/")
        )
        guard source.standardizedFileURL != destination.standardizedFileURL,
              FileManager.default.fileExists(atPath: source.path)
        else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        writeIdentity(of: space, in: destination)
    }

    /// Moves a space's folder to the Trash, for a space deleted in the app.
    ///
    /// A folder that is already gone is not an error — that is the case where the deletion came
    /// *from* the folder being removed in the first place.
    /// `claimedBy` is the space whose folder this is supposed to be, and the folder must agree.
    ///
    /// The path here is recomputed from a space's *name*, so it is a guess about which directory
    /// belongs to which space — and this method moves that directory to the Trash. The guess is wrong
    /// in ordinary use: delete a folder in Finder and immediately make a new one with the same name,
    /// and the path now points at the new folder. Before this check, whether that folder survived
    /// depended on a caller two files away passing the right flag, and nothing failed if it did not.
    ///
    /// So the folder is asked whether it is the one being deleted. Its `_space.md` has to name the
    /// space. A folder that claims nothing, or claims a different space, is left alone and logged —
    /// which makes the destructive branch safe regardless of how it is reached.
    func retireFolder(at components: [String], claimedBy spaceID: UUID?) throws {
        guard !components.isEmpty else { return }
        let directory = rootURL.appendingPathComponent(components.joined(separator: "/"))
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        if let spaceID {
            let spaceFile = directory.appendingPathComponent(SpaceFile.filename)
            let claimed = (try? String(contentsOf: spaceFile, encoding: .utf8))
                .flatMap(SpaceFile.identity(from:))?.id

            guard claimed == spaceID else {
                logger.error(
                    "Refused to trash a folder that does not claim the space being deleted"
                )
                return
            }
        }

        try retireFile(directory)
    }
}
