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

    @Test("Body text below the note is preserved for a future space description")
    func bodyPreserved() throws {
        let text = SpaceFile.render(space("Work")) + "\nMy notes about this space.\n"
        let restored = try #require(SpaceFile.identity(from: text))
        #expect(restored.id != nil as UUID?)
        #expect(SpaceFile.description(from: text)?.contains("My notes") == true)
    }

    // MARK: - Not a document

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

    @Test("Reading applies identity and appearance onto a space")
    func appliesToSpace() throws {
        let original = space("Work")
        let text = SpaceFile.render(original)

        // A space discovered from a folder, before its file was read.
        var discovered = Space(name: "Work")
        try SpaceFile.apply(text, to: &discovered)

        #expect(discovered.id == original.id)
        #expect(discovered.icon == "briefcase")
        #expect(discovered.color == "blue")
        #expect(discovered.sortOrder == 10)
    }

    @Test("Applying keeps the folder's name, since the folder is the naming authority")
    func nameNotOverwritten() throws {
        let text = SpaceFile.render(space("Old Name"))
        var renamed = Space(name: "New Name")
        try SpaceFile.apply(text, to: &renamed)

        #expect(renamed.name == "New Name")
    }

    @Test("Applying a file with no identity throws rather than half-applying")
    func applyRequiresIdentity() {
        var subject = Space(name: "Work")
        #expect(throws: (any Error).self) {
            try SpaceFile.apply("---\nicon: folder\n---\n", to: &subject)
        }
    }
}
