import Foundation
@testable import Logue
import Testing

/// Turning bytes on disk into text, before anything tries to read it as markdown.
///
/// Every case here was a falsifiable claim in review with nothing asserting it. The encoding
/// ladder in particular is easy to get subtly wrong in a way no one notices until someone's
/// accented note imports as CJK.
@Suite("Import file reading")
struct ImportFileReadingTests {
    private func temporaryFile(named name: String, containing data: Data) throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - Encodings

    @Test("A UTF-8 file reads back unchanged")
    func utf8RoundTrips() throws {
        let url = try temporaryFile(named: "n.md", containing: Data("# Café résumé\n\n内容".utf8))
        let text = try DocumentStore.readText(at: url)
        #expect(text == "# Café résumé\n\n内容")
    }

    /// The bug this ladder exists for. UTF-16 without a byte-order mark assumes big-endian and
    /// accepts almost any byte sequence, so `Café résumé` came back as `䍡曩⁲畭湡整潫`.
    @Test("A Latin-1 file is not silently decoded as CJK")
    func latin1IsNotMistakenForUTF16() throws {
        let latin1 = try #require("Café résumé".data(using: .isoLatin1))
        let url = try temporaryFile(named: "n.md", containing: latin1)

        let text = try DocumentStore.readText(at: url)
        #expect(text == "Café résumé")
        #expect(!text.contains("䍡"))
    }

    @Test("A UTF-16 file with a byte-order mark is decoded as UTF-16")
    func utf16WithBOMIsDecoded() throws {
        let utf16 = try #require("# Heading\nBody".data(using: .utf16))
        let url = try temporaryFile(named: "n.md", containing: utf16)

        let text = try DocumentStore.readText(at: url)
        #expect(text == "# Heading\nBody")
    }

    // MARK: - Binaries

    /// Latin-1 maps every byte, so the encoding ladder alone can never reject anything. Without a
    /// separate check a `.dylib` renamed `.md` imported as mojibake — and in markdown mode was
    /// then written straight back out as a `.md` file.
    @Test("A binary renamed .md is rejected rather than imported as mojibake")
    func binaryIsRejected() throws {
        var bytes = Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01])
        bytes.append(Data(repeating: 0, count: 512))
        let url = try temporaryFile(named: "libthing.md", containing: bytes)

        #expect(throws: (any Error).self) {
            try DocumentStore.readText(at: url)
        }
    }

    @Test("A single NUL is enough to reject a file")
    func nulRejects() {
        #expect(!DocumentStore.looksLikeText("Perfectly ordinary prose\u{0}and more"))
    }

    /// The check has to be blunt in one direction only. Notes containing the odd control character
    /// are real, and rejecting them would be worse than the mojibake it prevents.
    @Test("Ordinary text with tabs, newlines and the occasional control character is accepted")
    func textWithControlCharactersIsAccepted() {
        #expect(DocumentStore.looksLikeText("# Title\n\n\tIndented\r\nWindows line\n"))
        #expect(DocumentStore.looksLikeText("A note with a form feed \u{0C} in it."))
        #expect(DocumentStore.looksLikeText("Emoji 👩‍💻 and 日本語 and — dashes."))
        #expect(DocumentStore.looksLikeText(""))
    }

    // MARK: - Size

    @Test("A file over the size limit is rejected before it is read")
    func oversizedIsRejected() throws {
        let big = Data(repeating: UInt8(ascii: "x"), count: MarkdownImport.maxFileBytes + 1)
        let url = try temporaryFile(named: "big.md", containing: big)

        #expect(throws: MarkdownImport.ImportError.self) {
            try DocumentStore.readText(at: url)
        }
    }

    @Test("A file that is not there fails rather than reading as empty")
    func missingFileFails() {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        #expect(throws: (any Error).self) {
            try DocumentStore.readText(at: url)
        }
    }

    // MARK: - Walking a vault

    private func vault() throws -> URL {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files: [String: String] = [
            "Inbox.md": "# Inbox\n\nTop level.",
            "Projects/Apollo.md": "# Apollo\n\nOne.",
            "Projects/Notes/Deep.md": "# Deep\n\nTwo.",
            "Attachments/diagram.png": "not a note",
            ".obsidian/workspace.json": "{}",
        ]
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
        return root
    }

    /// A vault is a tree, and importing it one folder at a time — flattened into one space — was
    /// the whole shape of the problem this walk exists for.
    @Test("A chosen folder is walked, and subfolders keep their place in the tree")
    func directoryIsWalkedIntoPaths() throws {
        let scanned = DocumentStore.collect(from: [try vault()], storedRoot: nil)

        #expect(scanned.files[[]]?.map(\.name) == ["Inbox.md"])
        #expect(scanned.files[["Projects"]]?.map(\.name) == ["Apollo.md"])
        #expect(scanned.files[["Projects", "Notes"]]?.map(\.name) == ["Deep.md"])
    }

    /// A vault is full of images and PDFs. Reporting every one as "skipped" would bury the
    /// failures that actually need the user's attention.
    @Test("Attachments and hidden config are passed over without being reported")
    func attachmentsAreNotReportedAsSkipped() throws {
        let scanned = DocumentStore.collect(from: [try vault()], storedRoot: nil)

        #expect(scanned.skipped.isEmpty)
        #expect(scanned.files[["Attachments"]] == nil)
        #expect(scanned.files.keys.contains { $0.contains(".obsidian") } == false)
    }

    /// A file the user picked by hand is different: they meant that one, so silence would read
    /// as the import having worked.
    @Test("A hand-picked file of the wrong type is reported")
    func handPickedWrongTypeIsReported() throws {
        let url = try temporaryFile(named: "photo.png", containing: Data("x".utf8))
        let scanned = DocumentStore.collect(from: [url], storedRoot: nil)

        #expect(scanned.files.isEmpty)
        #expect(scanned.skipped.map(\.file) == ["photo.png"])
    }

    @Test("Files already in the Logue folder are refused before being read")
    func alreadyStoredIsRefused() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("note.md")
        try Data("# Note".utf8).write(to: url)

        let storedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let scanned = DocumentStore.collect(from: [url], storedRoot: storedRoot)

        #expect(scanned.files.isEmpty)
        #expect(scanned.skipped.first?.reason == "already in the Logue folder")
    }

    // MARK: - End to end

    @Test("A frontmatter file on disk becomes a document")
    func readProducesADocument() throws {
        let contents = "---\ntitle: From Obsidian\ntags: [a, b]\n---\n# Heading\n\nBody."
        let url = try temporaryFile(named: "note.md", containing: Data(contents.utf8))

        let document = try DocumentStore.read(url).get()
        #expect(document.title == "From Obsidian")
        #expect(document.tags == ["a", "b"])
        #expect(document.body == "# Heading\n\nBody.")
    }
}
