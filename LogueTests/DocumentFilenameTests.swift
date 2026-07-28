import Foundation
@testable import Logue
import Testing

/// Filenames for mirror files.
///
/// These are written to a user-visible directory from user-controlled titles, so this
/// is a path-safety boundary as well as a naming concern.
@Suite("DocumentFilename")
struct DocumentFilenameTests {
    private func document(_ title: String) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        return doc
    }

    @Test("A simple title becomes a readable filename")
    func simpleTitle() {
        #expect(DocumentFilename.filename(for: document("Project Alpha")) == "Project Alpha.md")
    }

    @Test("Path separators are removed so a title cannot escape the directory")
    func rejectsPathSeparators() {
        let name = DocumentFilename.filename(for: document("../../etc/passwd"))
        #expect(name.contains("/") == false)
        #expect(name.contains("..") == false)
    }

    @Test("A colon is removed, since it is a path separator on some filesystems")
    func removesColon() {
        #expect(DocumentFilename.filename(for: document("Plan: Q3")).contains(":") == false)
    }

    @Test("Leading dots are removed so the file is not hidden")
    func removesLeadingDot() {
        #expect(DocumentFilename.filename(for: document(".hidden")).hasPrefix(".") == false)
    }

    @Test("Control characters and newlines are removed")
    func removesControlCharacters() {
        let name = DocumentFilename.filename(for: document("a\nb\tc"))
        #expect(name.contains("\n") == false)
        #expect(name.contains("\t") == false)
    }

    @Test("An empty title falls back to a usable name")
    func emptyTitleFallsBack() {
        let name = DocumentFilename.filename(for: document("   "))
        #expect(name.hasSuffix(".md"))
        #expect(name.count > 3)
    }

    @Test("A title of only illegal characters falls back")
    func illegalOnlyTitleFallsBack() {
        let name = DocumentFilename.filename(for: document("///"))
        #expect(name.hasSuffix(".md"))
        #expect(name.contains("/") == false)
    }

    @Test("An over-long title is truncated, leaving room for the extension")
    func truncatesLongTitle() {
        let name = DocumentFilename.filename(for: document(String(repeating: "a", count: 500)))
        #expect(name.utf8.count <= DocumentFilename.maxFilenameBytes)
        #expect(name.hasSuffix(".md"))
    }

    @Test("Unicode titles are preserved")
    func preservesUnicode() {
        #expect(DocumentFilename.filename(for: document("会議メモ")) == "会議メモ.md")
    }

    @Test("An emoji title is preserved")
    func preservesEmoji() {
        #expect(DocumentFilename.filename(for: document("👩‍💻 notes")) == "👩‍💻 notes.md")
    }

    @Test("The same document always yields the same filename")
    func deterministic() {
        let doc = document("Project Alpha")
        #expect(DocumentFilename.filename(for: doc) == DocumentFilename.filename(for: doc))
    }

    // MARK: - Collisions

    @Test("Two documents sharing a title get distinct filenames")
    func disambiguatesCollision() {
        let first = document("Same Title")
        let second = document("Same Title")
        let taken = [DocumentFilename.filename(for: first)]
        let name = DocumentFilename.filename(for: second, avoiding: Set(taken))
        #expect(name != taken[0])
        #expect(name.hasSuffix(".md"))
    }

    @Test("Disambiguation is stable for the same document and taken set")
    func disambiguationStable() {
        let doc = document("Same Title")
        let taken = Set(["Same Title.md"])
        #expect(
            DocumentFilename.filename(for: doc, avoiding: taken)
                == DocumentFilename.filename(for: doc, avoiding: taken)
        )
    }

    @Test("A document keeps its plain name when nothing else has taken it")
    func noSuffixWhenFree() {
        #expect(DocumentFilename.filename(for: document("Free"), avoiding: []) == "Free.md")
    }

    @Test("Several collisions each resolve to a distinct name")
    func multipleCollisions() {
        var taken: Set<String> = []
        var names: [String] = []
        for _ in 0 ..< 4 {
            let name = DocumentFilename.filename(for: document("Dup"), avoiding: taken)
            taken.insert(name)
            names.append(name)
        }
        #expect(Set(names).count == 4)
    }
}
