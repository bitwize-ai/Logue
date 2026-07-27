import Foundation

/// One pass over the markdown folder, from files to a plan.
///
/// Separate from `DocumentStorage` and takes its root as a parameter, so the whole chain —
/// folders to spaces, files to documents, documents to a plan — can be run against a
/// temporary directory. Testing the links individually is not enough here: three features in
/// this codebase have shipped with every unit passing and the chain between them broken.
struct MarkdownFolderScan {
    let rootURL: URL
    let echoFilter: WriteEchoFilter?

    init(rootURL: URL, echoFilter: WriteEchoFilter? = nil) {
        self.rootURL = rootURL
        self.echoFilter = echoFilter
    }

    private var migrator: MarkdownStorageMigrator {
        MarkdownStorageMigrator(rootURL: rootURL, echoFilter: echoFilter)
    }

    // MARK: - Step one: folders

    /// Folders with no space yet, parents first.
    ///
    /// Separate from the plan because it has to happen first: a document in a folder that has
    /// no space would otherwise resolve to no space and be filed at the top level.
    func spaceCreations(in spaces: [Space]) -> [SpaceFolderAdoption.Creation] {
        SpaceFolderAdoption.creations(forDirectoryPaths: migrator.directories(), in: spaces)
    }

    /// The identity a folder claims for itself, so a rename stays the same space.
    func identity(forDirectoryComponents components: [String]) -> SpaceFile.Identity? {
        migrator.spaceIdentity(atDirectoryComponents: components)
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
        let imported = migrator.importAll(knownSpaces: spaces)
        let adopted = imported.unidentifiedFiles.compactMap {
            migrator.adopt(fileAt: $0, knownSpaces: spaces)
        }

        return ExternalChangePlanner.plan(
            scanned: imported.documents, adopted: adopted, known: known
        )
    }
}
