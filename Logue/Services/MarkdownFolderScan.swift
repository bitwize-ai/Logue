import Foundation

/// One pass over the markdown folder, from files to a plan.
///
/// Separate from `DocumentStorage` and takes its root as a parameter, so the whole chain —
/// folders to spaces, files to documents, documents to a plan — can be run against a
/// temporary directory. Testing the links individually is not enough here: three features in
/// this codebase have shipped with every unit passing and the chain between them broken.
struct MarkdownFolderScan: Sendable {
    let rootURL: URL

    private var migrator: MarkdownStorageMigrator {
        MarkdownStorageMigrator(rootURL: rootURL)
    }

    /// Whether the folder is there at all.
    ///
    /// Checked before anything else. An unmounted volume, a folder the user moved, or a sync that
    /// has not finished all look identical to "every folder was deleted" — and the answer to that
    /// would be to empty the library. So a missing root means do nothing.
    var isRootPresent: Bool {
        FileManager.default.fileExists(atPath: rootURL.path)
    }

    // MARK: - Step zero: folders that are gone

    /// Spaces whose folder no longer exists.
    ///
    /// Only meaningful because the app writes a folder as soon as a space is created and moves it
    /// whenever the space is renamed — so a space with no folder can only be one the user removed
    /// from Finder.
    func vanishedSpaceIDs(in spaces: [Space]) -> Set<UUID> {
        guard isRootPresent else { return [] }

        // Two independent ways of finding a space's folder, and either one counts. The identity
        // index is the good one, because it survives a rename. The path check is the safety net:
        // without it, anything that stops us *reading* `_space.md` — the user deleting it, a
        // permissions error, an iCloud placeholder, a write that failed earlier — was read as "the
        // folder is gone", and the answer to that is to delete the space and trash everything in
        // it. A folder sitting right there in Finder must never be read that way.
        let folders = migrator.spaceFolderMap(in: spaces)
        var present = folders.claimedSpaceIDs
        for space in spaces where !present.contains(space.id) {
            let directory = migrator.folderURL(forSpace: space.id, in: spaces, folders: folders)
            if FileManager.default.fileExists(atPath: directory.path) {
                present.insert(space.id)
            }
        }

        return SpaceFolderAdoption.vanishedSpaceIDs(in: spaces, folders: present)
    }

    // MARK: - Step one: folders

    /// Folders with no space yet, parents first.
    ///
    /// Separate from the plan because it has to happen first: a document in a folder that has
    /// no space would otherwise resolve to no space and be filed at the top level.
    func spaceCreations(in spaces: [Space]) -> [SpaceFolderAdoption.Creation] {
        SpaceFolderAdoption.creations(
            forDirectoryPaths: migrator.directories(), in: spaces, folders: migrator.spaceFolderMap(in: spaces)
        )
    }

    /// Spaces whose folder was renamed or moved outside the app.
    func folderRenames(in spaces: [Space]) -> [SpaceFolderAdoption.FolderRename] {
        guard isRootPresent else { return [] }
        return SpaceFolderAdoption.renames(in: spaces, folders: migrator.spaceFolderMap(in: spaces))
    }

    /// Folders duplicated in Finder, each claiming a space another folder already claims.
    func duplicatedSpaceFolders(in spaces: [Space] = []) -> [[String]] {
        migrator.spaceFolderMap(in: spaces).duplicatedFolders
    }

    /// Files carrying an identifier another file already claims.
    func duplicatedDocumentFiles() -> [URL] {
        migrator.documentFiles().duplicates
    }

    /// The identity a folder claims for itself, so a rename stays the same space.
    func identity(forDirectoryComponents components: [String]) -> SpaceFile.Identity? {
        migrator.spaceIdentity(atDirectoryComponents: components)
    }

    /// Writes one space's identity into the folder it was adopted from.
    func writeSpaceIdentity(for space: Space, atComponents components: [String]) {
        migrator.writeSpaceIdentity(for: space, atComponents: components)
    }

    /// Gives every space a `_space.md`, so folders made outside the app gain an identity.
    func writeSpaceIdentities(spaces: [Space]) {
        migrator.writeSpaceIdentities(spaces: spaces)
    }

    // MARK: - Step two: documents

    /// What the folder says should change, given the spaces that now exist.
    ///
    /// Files with no identifier are adopted as new documents — and the identifier is written
    /// into them as part of that, which is the one write a scan performs. Without it the next
    /// scan would adopt the same file again.
    func plan(spaces: [Space], known: [DocumentContent]) -> ExternalChangePlan {
        // The same guard as `vanishedSpaceIDs`, kept here as well rather than left to the caller:
        // a missing root reads as "no files at all", and the honest-looking conclusion from that
        // is to trash every document in the library.
        guard isRootPresent else { return ExternalChangePlan() }

        let imported = migrator.importAll(knownSpaces: spaces)
        let adopted = imported.unidentifiedFiles.compactMap {
            migrator.adopt(fileAt: $0, knownSpaces: spaces)
        }

        return ExternalChangePlanner.plan(
            scanned: imported.documents,
            adopted: adopted,
            known: known,
            ambiguous: imported.ambiguousIdentifiers
        )
    }
}
