import Foundation
@testable import Logue
import Testing

/// `_space.md` — the visible file that gives a folder its space identity.
///
/// Visible rather than a dotfile on purpose: someone who breaks hidden state has no way
/// to learn why their space lost its icon.
@Suite("SpaceFile")
struct SpaceFileTests {
    private func space(_ name: String) -> Space {
        Space(name: name, sortOrder: 10, icon: "briefcase", color: "blue")
    }

    // MARK: - Round trip

    @Test("Identity and appearance survive a write and a read")
    func roundTrip() throws {
        let original = space("Work")
        let restored = try #require(SpaceFile.identity(from: SpaceFile.render(original)))

        #expect(restored.id == original.id)
        #expect(restored.icon == "briefcase")
        #expect(restored.color == "blue")
        #expect(restored.sortOrder == 10)
    }

    @Test("A space with no icon or colour round-trips")
    func minimalRoundTrip() throws {
        let original = Space(name: "Plain")
        let restored = try #require(SpaceFile.identity(from: SpaceFile.render(original)))
        #expect(restored.id == original.id)
        #expect(restored.icon == nil)
    }

    @Test("The rendered file is byte-stable")
    func deterministic() {
        let subject = space("Work")
        #expect(SpaceFile.render(subject) == SpaceFile.render(subject))
    }

    // MARK: - The human-facing note

    @Test("The file explains itself, so a reader knows not to edit the identity")
    func carriesExplanation() {
        let text = SpaceFile.render(space("Work"))
        #expect(text.contains("Managed by Logue"))
        #expect(text.lowercased().contains("editing"))
    }

    @Test("It is marked as app-managed")
    func markedManaged() {
        #expect(SpaceFile.render(space("Work")).contains(SpaceFile.managedKey))
    }

    // MARK: - Reading

    @Test("A file with no space id yields nothing rather than a guess")
    func noIdentity() {
        #expect(SpaceFile.identity(from: "---\nicon: folder\n---\n") == nil)
    }

    @Test("A malformed space id yields nothing")
    func malformedIdentity() {
        #expect(SpaceFile.identity(from: "---\n\(SpaceFile.identifierKey): nope\n---\n") == nil)
    }

    @Test("A missing sort order falls back rather than failing the read")
    func missingSortOrder() throws {
        let text = "---\n\(SpaceFile.identifierKey): 0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40\n---\n"
        let restored = try #require(SpaceFile.identity(from: text))
        #expect(restored.sortOrder == 0)
    }

    @Test("The filename is recognised, so it is never imported as a document")
    func filenameRecognised() {
        #expect(SpaceFile.isSpaceFile(filename: SpaceFile.filename))
        #expect(SpaceFile.isSpaceFile(filename: "notes.md") == false)
    }

    @Test("Content carrying a space id is recognised even under another filename")
    func contentRecognised() {
        let text = SpaceFile.render(space("Work"))
        #expect(SpaceFile.isSpaceFile(contents: text))
        #expect(SpaceFile.isSpaceFile(contents: "---\ntitle: A\n---\nbody") == false)
    }

    // MARK: - Applying back
}

/// Keeping what the user wrote in a space file.
@Suite("Space file body")
struct SpaceFileBodyTests {
    @Test("Prose added below the managed note survives a rewrite")
    func keepsUserProse() {
        let space = Space(name: "Work")
        let edited = SpaceFile.render(space) + "\nEverything client-facing lives here.\n"

        let rewritten = SpaceFile.render(space, keepingBodyOf: edited)

        #expect(rewritten.contains("Everything client-facing lives here."))
        #expect(SpaceFile.identity(from: rewritten)?.id == space.id)
    }

    @Test("A rewrite does not accumulate copies of the note or the prose")
    func doesNotAccumulate() {
        let space = Space(name: "Work")
        var file = SpaceFile.render(space) + "\nMine.\n"

        for _ in 0 ..< 3 {
            file = SpaceFile.render(space, keepingBodyOf: file)
        }

        #expect(file.components(separatedBy: "Mine.").count - 1 == 1)
        #expect(file.components(separatedBy: "Managed by Logue").count - 1 == 1)
    }

    @Test("A file with no prose stays as it was")
    func unchangedWithoutProse() {
        let space = Space(name: "Work")
        let plain = SpaceFile.render(space)

        #expect(SpaceFile.render(space, keepingBodyOf: plain) == plain)
    }

    @Test("A changed icon reaches the file while the prose stays")
    func updatesIdentityKeepingProse() {
        var space = Space(name: "Work")
        let edited = SpaceFile.render(space) + "\nMine.\n"
        space.icon = "hammer"

        let rewritten = SpaceFile.render(space, keepingBodyOf: edited)

        #expect(SpaceFile.identity(from: rewritten)?.icon == "hammer")
        #expect(rewritten.contains("Mine."))
    }
}
