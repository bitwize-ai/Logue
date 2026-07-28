import Foundation
@testable import Logue
import Testing

/// Mapping the space hierarchy onto directories, in both directions.
///
/// Space names are user-controlled and become real directory names, so every
/// component is a path-safety boundary — the same one `DocumentFilename` guards for
/// files.
@Suite("SpaceFolderLayout")
struct SpaceFolderLayoutTests {
    private func space(_ name: String, parent: UUID? = nil, id: UUID = UUID()) -> Space {
        Space(id: id, name: name, parentID: parent)
    }

    private func document(_ title: String, space spaceID: UUID? = nil) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.spaceID = spaceID
        return doc
    }

    // MARK: - Space → directory components

    @Test("A document with no space sits at the documents folder root")
    func unfiledAtRoot() {
        let path = SpaceFolderLayout.directoryComponents(forSpace: nil, in: [])
        #expect(path.isEmpty)
    }

    @Test("A top-level space becomes one directory")
    func topLevelSpace() {
        let work = space("Work")
        #expect(SpaceFolderLayout.directoryComponents(forSpace: work.id, in: [work]) == ["Work"])
    }

    @Test("Nested spaces become nested directories, outermost first")
    func nestedSpaces() {
        let work = space("Work")
        let projects = space("Projects", parent: work.id)
        let alpha = space("Alpha", parent: projects.id)

        let path = SpaceFolderLayout.directoryComponents(forSpace: alpha.id, in: [work, projects, alpha])
        #expect(path == ["Work", "Projects", "Alpha"])
    }

    @Test("An unknown space id yields no components rather than a bogus path")
    func unknownSpace() {
        #expect(SpaceFolderLayout.directoryComponents(forSpace: UUID(), in: []).isEmpty)
    }

    @Test("A space whose parent is missing is treated as top level")
    func orphanedSpace() {
        let orphan = space("Orphan", parent: UUID())
        #expect(SpaceFolderLayout.directoryComponents(forSpace: orphan.id, in: [orphan]) == ["Orphan"])
    }

    /// A corrupted parent chain must not hang the app.
    @Test("A cycle in the parent chain is broken rather than looping forever")
    func cycleIsBroken() {
        let firstID = UUID()
        let secondID = UUID()
        let first = Space(id: firstID, name: "A", parentID: secondID)
        let second = Space(id: secondID, name: "B", parentID: firstID)

        let path = SpaceFolderLayout.directoryComponents(forSpace: firstID, in: [first, second])
        #expect(path.count <= SpaceFolderLayout.maxDepth)
    }

    @Test("Depth is capped so a pathological hierarchy cannot exceed filesystem limits")
    func depthCapped() {
        var spaces: [Space] = []
        var parent: UUID?
        for index in 0 ..< (SpaceFolderLayout.maxDepth + 10) {
            let next = space("Level \(index)", parent: parent)
            spaces.append(next)
            parent = next.id
        }
        let deepest = spaces.last?.id
        let path = SpaceFolderLayout.directoryComponents(forSpace: deepest, in: spaces)
        #expect(path.count <= SpaceFolderLayout.maxDepth)
    }

    // MARK: - Component safety

    @Test("Path separators in a space name are removed")
    func stripsSeparators() {
        let bad = space("../etc")
        let path = SpaceFolderLayout.directoryComponents(forSpace: bad.id, in: [bad])
        #expect(path.first?.contains("/") == false)
        #expect(path.first?.contains("..") == false)
    }

    @Test("A space named only of illegal characters falls back to a usable name")
    func illegalNameFallsBack() {
        let bad = space("///")
        let path = SpaceFolderLayout.directoryComponents(forSpace: bad.id, in: [bad])
        #expect(path.first?.isEmpty == false)
    }

    @Test("Unicode space names are preserved")
    func preservesUnicode() {
        let space = space("会議")
        #expect(SpaceFolderLayout.directoryComponents(forSpace: space.id, in: [space]) == ["会議"])
    }

    @Test("Two sibling spaces with the same name get distinct directories")
    func siblingNameCollision() {
        let parentID = UUID()
        let parent = Space(id: parentID, name: "Work", parentID: nil)
        let first = space("Dup", parent: parentID)
        let second = space("Dup", parent: parentID)
        let spaces = [parent, first, second]

        let firstPath = SpaceFolderLayout.directoryComponents(forSpace: first.id, in: spaces)
        let secondPath = SpaceFolderLayout.directoryComponents(forSpace: second.id, in: spaces)
        #expect(firstPath != secondPath)
    }

    // MARK: - Full relative path

    @Test("Directory components map back to an existing space")
    func resolvesExistingSpace() {
        let work = space("Work")
        let projects = space("Projects", parent: work.id)
        let resolved = SpaceFolderLayout.spaceID(
            forDirectoryComponents: ["Work", "Projects"], in: [work, projects]
        )
        #expect(resolved == projects.id)
    }

    @Test("Matching a directory to a space is case-insensitive")
    func resolvesCaseInsensitively() {
        let work = space("Work")
        #expect(SpaceFolderLayout.spaceID(forDirectoryComponents: ["work"], in: [work]) == work.id)
    }

    @Test("No components means the documents folder root, which is no space")
    func rootResolvesToNil() {
        #expect(SpaceFolderLayout.spaceID(forDirectoryComponents: [], in: []) == nil)
    }

    @Test("An unmatched directory resolves to nothing, so the caller can create it")
    func unmatchedResolvesToNil() {
        #expect(SpaceFolderLayout.spaceID(forDirectoryComponents: ["New"], in: []) == nil)
    }

    @Test("A partially matching path resolves to nothing rather than the nearest ancestor")
    func partialMatchIsNotEnough() {
        let work = space("Work")
        let resolved = SpaceFolderLayout.spaceID(
            forDirectoryComponents: ["Work", "Unknown"], in: [work]
        )
        #expect(resolved == nil)
    }
}
