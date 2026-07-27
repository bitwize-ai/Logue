import Foundation
@testable import Logue
import Testing

/// Turning folders made outside the app into spaces.
///
/// The first test is the one that matters most: a folder that already has a space must
/// produce nothing. An earlier version of this feature created a near-duplicate space on
/// every pass, which then wrote a new folder, which read as another new folder — a library
/// that grew without end.
@Suite("Space folder adoption")
struct SpaceFolderAdoptionTests {
    @Test("A folder that already has a space creates nothing")
    func existingFolderIsQuiet() {
        let work = Space(name: "Work")

        #expect(SpaceFolderAdoption.creations(forDirectoryPaths: [["Work"]], in: [work]).isEmpty)
    }

    @Test("Scanning the same folders repeatedly never creates more")
    func repeatedScansConverge() {
        var spaces: [Space] = []
        let paths = [["Work"], ["Work", "Projects"]]

        // Two rounds: whatever the first creates, the second must find nothing to do.
        for creation in SpaceFolderAdoption.creations(forDirectoryPaths: paths, in: spaces) {
            let parentID = MirrorLayout.spaceID(
                forDirectoryComponents: creation.parentComponents, in: spaces
            )
            spaces.append(Space(name: creation.name, parentID: parentID))
        }

        #expect(spaces.count == 2)
        #expect(SpaceFolderAdoption.creations(forDirectoryPaths: paths, in: spaces).isEmpty)
    }

    @Test("A new top-level folder becomes a space")
    func newFolderIsCreated() {
        let creations = SpaceFolderAdoption.creations(forDirectoryPaths: [["Reading"]], in: [])

        #expect(creations == [.init(name: "Reading", parentComponents: [])])
    }

    /// A whole tree can appear in one drag, so ancestors are created even though only the
    /// leaf held a file.
    @Test("Nested folders are created parents first")
    func createsAncestorsInOrder() {
        let creations = SpaceFolderAdoption.creations(
            forDirectoryPaths: [["Work", "Projects", "Q3"]], in: []
        )

        #expect(creations.map(\.name) == ["Work", "Projects", "Q3"])
        #expect(creations.last?.parentComponents == ["Work", "Projects"])
    }

    @Test("An existing parent is reused rather than recreated")
    func reusesExistingParent() {
        let work = Space(name: "Work")
        let creations = SpaceFolderAdoption.creations(
            forDirectoryPaths: [["Work", "Projects"]], in: [work]
        )

        #expect(creations == [.init(name: "Projects", parentComponents: ["Work"])])
    }

    @Test("Two paths sharing a parent create that parent once")
    func sharedParentCreatedOnce() {
        let creations = SpaceFolderAdoption.creations(
            forDirectoryPaths: [["Work", "Alpha"], ["Work", "Beta"]], in: []
        )

        #expect(creations.filter { $0.name == "Work" }.count == 1)
        #expect(creations.count == 3)
    }

    @Test("Files at the root create nothing")
    func rootNeedsNoSpace() {
        #expect(SpaceFolderAdoption.creations(forDirectoryPaths: [[]], in: []).isEmpty)
        #expect(SpaceFolderAdoption.creations(forDirectoryPaths: [], in: []).isEmpty)
    }

    /// Two folders in different parents can share a name without either being mistaken for
    /// the other.
    @Test("Same-named folders under different parents are separate spaces")
    func sameNameUnderDifferentParents() {
        let creations = SpaceFolderAdoption.creations(
            forDirectoryPaths: [["Work", "Notes"], ["Personal", "Notes"]], in: []
        )

        #expect(creations.filter { $0.name == "Notes" }.count == 2)
    }

    // MARK: - Renamed folders

    /// A renamed folder must move its space, not replace it. Replacing would lose the icon,
    /// colour and sidebar position — and it is the same space by every meaningful measure.
    @Test("A folder whose space file names an existing space is a rename")
    func claimedIdentityIsARename() {
        let work = Space(name: "Work")
        let creation = SpaceFolderAdoption.Creation(name: "Client Work", parentComponents: [])

        let resolution = SpaceFolderAdoption.resolve(creation, claimedID: work.id, in: [work])

        #expect(resolution == .rename(id: work.id, to: "Client Work", parentComponents: []))
    }

    @Test("A folder with no space file is a new space")
    func unclaimedFolderIsCreated() {
        let creation = SpaceFolderAdoption.Creation(name: "Reading", parentComponents: [])

        let resolution = SpaceFolderAdoption.resolve(creation, claimedID: nil, in: [])

        #expect(resolution == .create(id: nil, name: "Reading", parentComponents: []))
    }

    /// A folder restored from a backup keeps the identity it had, so the space it was comes
    /// back rather than a lookalike.
    @Test("A claimed identifier matching no space is kept, not replaced")
    func unknownClaimedIdentityIsKept() {
        let restored = UUID()
        let creation = SpaceFolderAdoption.Creation(name: "Archive", parentComponents: [])

        let resolution = SpaceFolderAdoption.resolve(creation, claimedID: restored, in: [])

        #expect(resolution == .create(id: restored, name: "Archive", parentComponents: []))
    }

    @Test("A folder moved under another folder is a rename with a new parent")
    func movedFolderKeepsIdentity() {
        let notes = Space(name: "Notes")
        let creation = SpaceFolderAdoption.Creation(name: "Notes", parentComponents: ["Work"])

        let resolution = SpaceFolderAdoption.resolve(creation, claimedID: notes.id, in: [notes])

        #expect(resolution == .rename(id: notes.id, to: "Notes", parentComponents: ["Work"]))
    }

    @Test("The order does not depend on the order the folders were found in")
    func orderIsStable() {
        let paths = [["Work", "Projects"], ["Work"], ["Reading"]]
        let forwards = SpaceFolderAdoption.creations(forDirectoryPaths: paths, in: [])
        let backwards = SpaceFolderAdoption.creations(forDirectoryPaths: paths.reversed(), in: [])

        #expect(forwards == backwards)
    }
}
