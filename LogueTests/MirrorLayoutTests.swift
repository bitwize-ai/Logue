import Foundation
@testable import Logue
import Testing

/// Mapping the space hierarchy onto directories, in both directions.
///
/// Space names are user-controlled and become real directory names, so every
/// component is a path-safety boundary — the same one `MirrorFilename` guards for
/// files.
@Suite("MirrorLayout")
struct MirrorLayoutTests {
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

    @Test("A document with no space sits at the mirror root")
    func unfiledAtRoot() {
        let path = MirrorLayout.directoryComponents(forSpace: nil, in: [])
        #expect(path.isEmpty)
    }

    @Test("A top-level space becomes one directory")
    func topLevelSpace() {
        let work = space("Work")
        #expect(MirrorLayout.directoryComponents(forSpace: work.id, in: [work]) == ["Work"])
    }

    @Test("Nested spaces become nested directories, outermost first")
    func nestedSpaces() {
        let work = space("Work")
        let projects = space("Projects", parent: work.id)
        let alpha = space("Alpha", parent: projects.id)

        let path = MirrorLayout.directoryComponents(forSpace: alpha.id, in: [work, projects, alpha])
        #expect(path == ["Work", "Projects", "Alpha"])
    }

    @Test("An unknown space id yields no components rather than a bogus path")
    func unknownSpace() {
        #expect(MirrorLayout.directoryComponents(forSpace: UUID(), in: []).isEmpty)
    }

    @Test("A space whose parent is missing is treated as top level")
    func orphanedSpace() {
        let orphan = space("Orphan", parent: UUID())
        #expect(MirrorLayout.directoryComponents(forSpace: orphan.id, in: [orphan]) == ["Orphan"])
    }

    /// A corrupted parent chain must not hang the app.
    @Test("A cycle in the parent chain is broken rather than looping forever")
    func cycleIsBroken() {
        let firstID = UUID()
        let secondID = UUID()
        let first = Space(id: firstID, name: "A", parentID: secondID)
        let second = Space(id: secondID, name: "B", parentID: firstID)

        let path = MirrorLayout.directoryComponents(forSpace: firstID, in: [first, second])
        #expect(path.count <= MirrorLayout.maxDepth)
    }

    @Test("Depth is capped so a pathological hierarchy cannot exceed filesystem limits")
    func depthCapped() {
        var spaces: [Space] = []
        var parent: UUID?
        for index in 0 ..< (MirrorLayout.maxDepth + 10) {
            let next = space("Level \(index)", parent: parent)
            spaces.append(next)
            parent = next.id
        }
        let deepest = spaces.last?.id
        let path = MirrorLayout.directoryComponents(forSpace: deepest, in: spaces)
        #expect(path.count <= MirrorLayout.maxDepth)
    }

    // MARK: - Component safety

    @Test("Path separators in a space name are removed")
    func stripsSeparators() {
        let bad = space("../etc")
        let path = MirrorLayout.directoryComponents(forSpace: bad.id, in: [bad])
        #expect(path.first?.contains("/") == false)
        #expect(path.first?.contains("..") == false)
    }

    @Test("A space named only of illegal characters falls back to a usable name")
    func illegalNameFallsBack() {
        let bad = space("///")
        let path = MirrorLayout.directoryComponents(forSpace: bad.id, in: [bad])
        #expect(path.first?.isEmpty == false)
    }

    @Test("Unicode space names are preserved")
    func preservesUnicode() {
        let space = space("会議")
        #expect(MirrorLayout.directoryComponents(forSpace: space.id, in: [space]) == ["会議"])
    }

    @Test("Two sibling spaces with the same name get distinct directories")
    func siblingNameCollision() {
        let parentID = UUID()
        let parent = Space(id: parentID, name: "Work", parentID: nil)
        let first = space("Dup", parent: parentID)
        let second = space("Dup", parent: parentID)
        let spaces = [parent, first, second]

        let firstPath = MirrorLayout.directoryComponents(forSpace: first.id, in: spaces)
        let secondPath = MirrorLayout.directoryComponents(forSpace: second.id, in: spaces)
        #expect(firstPath != secondPath)
    }

    // MARK: - Full relative path

    @Test("A document's path combines its space directories and filename")
    func documentRelativePath() {
        let work = space("Work")
        let doc = document("Notes", space: work.id)
        let path = MirrorLayout.relativePath(for: doc, in: [work], avoiding: [])
        #expect(path == "Work/Notes.md")
    }

    @Test("An unfiled document's path is just its filename")
    func unfiledRelativePath() {
        let path = MirrorLayout.relativePath(for: document("Notes"), in: [], avoiding: [])
        #expect(path == "Notes.md")
    }

    // MARK: - Directory → space

    @Test("Directory components map back to an existing space")
    func resolvesExistingSpace() {
        let work = space("Work")
        let projects = space("Projects", parent: work.id)
        let resolved = MirrorLayout.spaceID(
            forDirectoryComponents: ["Work", "Projects"], in: [work, projects]
        )
        #expect(resolved == projects.id)
    }

    @Test("Matching a directory to a space is case-insensitive")
    func resolvesCaseInsensitively() {
        let work = space("Work")
        #expect(MirrorLayout.spaceID(forDirectoryComponents: ["work"], in: [work]) == work.id)
    }

    @Test("No components means the mirror root, which is no space")
    func rootResolvesToNil() {
        #expect(MirrorLayout.spaceID(forDirectoryComponents: [], in: []) == nil)
    }

    @Test("An unmatched directory resolves to nothing, so the caller can create it")
    func unmatchedResolvesToNil() {
        #expect(MirrorLayout.spaceID(forDirectoryComponents: ["New"], in: []) == nil)
    }

    @Test("A partially matching path resolves to nothing rather than the nearest ancestor")
    func partialMatchIsNotEnough() {
        let work = space("Work")
        let resolved = MirrorLayout.spaceID(
            forDirectoryComponents: ["Work", "Unknown"], in: [work]
        )
        #expect(resolved == nil)
    }

    @Test("Missing space names are reported so they can be created in order")
    func reportsMissingComponents() {
        let work = space("Work")
        let missing = MirrorLayout.missingComponents(
            forDirectoryComponents: ["Work", "Projects", "Alpha"], in: [work]
        )
        #expect(missing == ["Projects", "Alpha"])
    }

    @Test("Nothing is missing when the whole path exists")
    func nothingMissingWhenResolved() {
        let work = space("Work")
        #expect(MirrorLayout.missingComponents(forDirectoryComponents: ["Work"], in: [work]).isEmpty)
    }
}
