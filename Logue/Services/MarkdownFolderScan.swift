import Foundation

/// One pass over the markdown folder, from files to a plan.
///
/// Separate from `DocumentStorage` and takes its root as a parameter, so the whole chain —
/// folders to spaces, files to documents, documents to a plan — can be run against a
/// temporary directory. Testing the links individually is not enough here: three features in
/// this codebase have shipped with every unit passing and the chain between them broken.
struct MarkdownFolderScan: Sendable {
    let rootURL: URL

    /// How long a file must have been untouched before it is adopted as a new document.
    ///
    /// Injectable so a test can adopt immediately. Production waits, because a file mid-write looks
    /// exactly like a file with no identifier, and adopting one overwrites content the user is still
    /// saving — a test that writes a file and scans in the same breath is not that case.
    var adoptionSettleSeconds: TimeInterval = AppConstants.Delays.adoptionSettleSeconds

    init(rootURL: URL, adoptionSettleSeconds: TimeInterval = AppConstants.Delays.adoptionSettleSeconds) {
        // Resolved for the same reason as in the migrator: the enumerator does not follow a symlinked
        // root, so an unresolved one walks as empty while every other check says the folder is there.
        self.rootURL = rootURL.resolvingSymlinksInPath()
        self.adoptionSettleSeconds = adoptionSettleSeconds
    }

    private var migrator: MarkdownStorageMigrator {
        MarkdownStorageMigrator(rootURL: rootURL)
    }

    /// Whether the folder is there at all.
    ///
    /// Checked before anything else. An unmounted volume, a folder the user moved, or a sync that
    /// has not finished all look identical to "every folder was deleted" — and the answer to that
    /// would be to empty the library. So a missing root means do nothing.
    var isRootPresent: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }

        // Present is not the same as readable. A folder we cannot list walks as empty, and an empty
        // walk used to mean "everything was deleted" — so the guard has to confirm the walk can
        // actually happen, not merely that something is at the path. A symlinked root is handled by
        // resolving it in `init`, not by refusing it: pointing this at a vault is the point.
        return canWalkRoot()
    }

    /// Whether the root can actually be enumerated, not merely stat'ed.
    private func canWalkRoot() -> Bool {
        guard (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) != nil else {
            return false
        }
        return true
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
    func plan(
        spaces: [Space],
        known: [DocumentContent],
        lastKnownFiles: [UUID: URL] = [:]
    ) -> ExternalChangePlan {
        // The same guard as `vanishedSpaceIDs`, kept here as well rather than left to the caller:
        // a missing root reads as "no files at all", and the honest-looking conclusion from that
        // is to trash every document in the library.
        guard isRootPresent else { return ExternalChangePlan() }

        let imported = migrator.importAll(knownSpaces: spaces)

        // Files are only adopted when the walk was whole and the file has settled. A file caught
        // mid-write parses as unidentified — that is exactly what a truncated file looks like — and
        // adopting it wrote our frontmatter over content the user was still saving, while the same
        // pass trashed the document that file *was*.
        let adopted = imported.isComplete
            ? imported.unidentifiedFiles
            .filter { hasSettled($0) }
            .compactMap { migrator.adopt(fileAt: $0, knownSpaces: spaces) }
            : []

        // The cross-check that makes absence mean something. An incomplete walk protects *every*
        // document, because we cannot say which part of the folder went unread.
        var stillOnDisk = migrator.documentsStillOnDisk(lastKnownFiles)
        stillOnDisk.formUnion(imported.unreadableIdentifiers)
        if !imported.isComplete {
            stillOnDisk.formUnion(known.map(\.id))
        }

        return ExternalChangePlanner.plan(
            scanned: imported.documents,
            adopted: adopted,
            known: known,
            ambiguous: imported.ambiguousIdentifiers,
            stillOnDisk: stillOnDisk
        )
    }

    /// Whether a file has stopped changing long enough to be safe to read as finished.
    ///
    /// The debounce before a scan is short — 0.2s of FSEvents coalescing plus 0.4s — and a large file
    /// or a network volume exceeds it easily. A file still being written is not a new document.
    private func hasSettled(_ url: URL) -> Bool {
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        else { return false }

        return Date().timeIntervalSince(modified) >= adoptionSettleSeconds
    }
}
