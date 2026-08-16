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
        let directory = avoidingTaskFolder(folderURL(forSpace: space.id, in: spaces, folders: folders))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeIdentity(of: space, in: directory)
    }

    /// A destination that is not the live tasks folder.
    ///
    /// A space named "Tasks" derives exactly the path the tasks folder occupies, and
    /// `createDirectory(withIntermediateDirectories: true)` succeeds silently on a directory
    /// that is already there — so `_space.md` would land inside it. From that moment the
    /// snapshot resolves the folder in the space's favour, every task file reads as an
    /// unidentified document, and the scan adopts and rewrites them: status, priority, due
    /// date and the task's identity gone from the only copy on disk.
    ///
    /// Steps over rather than refusing, so naming a space "Tasks" still works — the same rule
    /// the tasks side already applies when a space got to the name first. Only the colliding
    /// case behaves differently; every other path is returned untouched.
    /// - Parameter alreadyOccupying: the folder the space is in now, when it has one. Counted as
    ///   free, because a space already living in `Tasks 2` that is renamed back to "Tasks" should
    ///   stay put rather than step past its own folder to `Tasks 3` — which physically relocates
    ///   it and every document in it, and repeats on every attempt.
    func avoidingTaskFolder(_ directory: URL, alreadyOccupying source: URL? = nil) -> URL {
        guard TaskFolderStore(rootURL: directory).isMarkedTaskFolder else { return directory }

        let parent = directory.deletingLastPathComponent()
        let name = directory.lastPathComponent
        let occupied = source?.standardizedFileURL
        for suffix in 2 ... 20 {
            let candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            let isOwn = candidate.standardizedFileURL == occupied
            let isFree = isOwn
                || (!FileManager.default.fileExists(atPath: candidate.path)
                    && !TaskFolderStore(rootURL: candidate).isMarkedTaskFolder)
            if isFree {
                return candidate
            }
        }
        // Twenty variants all taken is not a real library. Returning the original would write
        // into the tasks folder, so give back a name that cannot collide instead.
        return parent.appendingPathComponent("\(name) \(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    /// Moves a space's folder, for a space renamed or re-parented in the app.
    ///
    /// The identity is rewritten afterwards so the moved folder still names its space.
    ///
    /// Both ends are checked before anything moves, for the same reason `retireFolder` checks
    /// before it trashes: `components` is derived from the space's *old name*, so it is a guess
    /// about which directory belongs to this space, and stepping a folder aside is precisely
    /// what makes a space's name and its folder disagree. A space named "Tasks" that was given
    /// `Tasks 2` derives `["Tasks"]` here — the live tasks folder — and renaming it then moved
    /// every task file out of it and stamped `_space.md` on top of them. Tasks written in
    /// markdown mode have no encrypted copy, so that folder held the only one.
    func moveFolder(from components: [String], for space: Space, in spaces: [Space]) throws {
        let source = rootURL.appendingPathComponent(components.joined(separator: "/"))
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        guard sourceBelongsTo(space, at: source) else { return }

        // The destination is name-derived on purpose: renaming a space is precisely the act of
        // asking for a folder named after the new name, so the folder map must not answer with
        // where the folder currently is. Only the *parents* are resolved by identity, so the
        // move cannot walk through a folder that is no longer where its name says it is.
        let destination = avoidingTaskFolder(
            destinationURL(for: space, in: spaces),
            alreadyOccupying: source
        )
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        writeIdentity(of: space, in: destination)
    }

    /// Whether the directory a rename is about to move really belongs to this space.
    ///
    /// A folder claiming nothing is accepted: a space created before this branch, or one whose
    /// `_space.md` a user deleted, still has a folder that is legitimately its own. A folder
    /// claiming a *different* space, or carrying the tasks marker, is refused and logged.
    private func sourceBelongsTo(_ space: Space, at source: URL) -> Bool {
        if TaskFolderStore(rootURL: source).isMarkedTaskFolder {
            logger.error("Refused to move the tasks folder as if it were a space folder")
            return false
        }

        let spaceFile = source.appendingPathComponent(SpaceFile.filename)
        guard let contents = try? String(contentsOf: spaceFile, encoding: .utf8),
              let claimed = SpaceFile.identity(from: contents)?.id
        else { return true }

        guard claimed == space.id else {
            logger.error("Refused to move a folder that claims a different space")
            return false
        }
        return true
    }

    /// Where a rename should put the folder: the new name, under the parents' *real* folders.
    ///
    /// The leaf is name-derived because that is what a rename asks for. The parents are not:
    /// deriving those from ancestor names walks `createDirectory(withIntermediateDirectories:)`
    /// straight through whatever now sits at a parent's name — including the live tasks folder,
    /// where the snapshot excludes the space from every later scan. Since the ancestor walk in
    /// `SpaceFolderMap` that folder then resolves to a path that does not exist, so the space
    /// reads as vanished and its documents are trashed.
    private func destinationURL(for space: Space, in spaces: [Space]) -> URL {
        let leaf = SpaceFolderLayout.directoryComponents(forSpace: space.id, in: spaces).last
            ?? space.name
        let parents = spaceFolderMap(in: spaces).components(forSpace: space.parentID, in: spaces)
        return rootURL.appendingPathComponent((parents + [leaf]).joined(separator: "/"))
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
