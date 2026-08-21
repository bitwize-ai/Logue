import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Logue

/// The one piece of attachment intake that is pure, and the one worth pinning.
///
/// The picker and the drop unpacking touch `NSOpenPanel` and `NSItemProvider`, neither of
/// which runs headlessly. The de-dupe rule does, and it is the part two surfaces could
/// disagree about now that both call it — which is exactly why it stopped being `private`.
@Suite("AttachmentIntake")
@MainActor
struct AttachmentIntakeTests {
    private func attachment(_ name: String) -> TempAttachment {
        TempAttachment(
            kind: .plainText,
            displayName: name,
            extractedText: "contents of \(name)",
            iconName: "doc"
        )
    }

    @Test("The same file arriving twice is added once")
    func duplicatesAreSkipped() {
        // Dragging a file twice is a slip, not a request for two copies.
        let existing = [attachment("notes.md")]
        let merged = AttachmentIntake.merging([attachment("notes.md")], into: existing)
        #expect(merged.count == 1)
    }

    @Test("Matching is by display name, not identity")
    func matchesOnName() {
        // The two drags carry different `TempAttachment` values — a fresh id each time, and
        // in the real case possibly a different security-scoped URL for one file on disk.
        // Comparing identity would let the same file in twice.
        let first = attachment("report.pdf")
        let second = attachment("report.pdf")
        #expect(first.id != second.id)
        #expect(AttachmentIntake.merging([second], into: [first]).count == 1)
    }

    @Test("Different files all arrive")
    func distinctFilesAreKept() {
        let merged = AttachmentIntake.merging(
            [attachment("b.txt"), attachment("c.txt")],
            into: [attachment("a.txt")]
        )
        #expect(merged.map(\.displayName) == ["a.txt", "b.txt", "c.txt"])
    }

    @Test("Order is preserved, with new files after the ones already staged")
    func orderIsStable() {
        // The chips read left to right in the order they were added; re-ordering on every
        // drop would move a chip out from under the pointer about to close it.
        let merged = AttachmentIntake.merging(
            [attachment("z.txt"), attachment("a.txt")],
            into: [attachment("m.txt")]
        )
        #expect(merged.map(\.displayName) == ["m.txt", "z.txt", "a.txt"])
    }

    @Test("A batch containing a duplicate keeps the rest")
    func partialDuplicateKeepsTheRest() {
        // Dropping a folder's worth of files where one is already staged should attach the
        // others rather than being treated as a repeat of the whole batch.
        let merged = AttachmentIntake.merging(
            [attachment("a.txt"), attachment("new.txt")],
            into: [attachment("a.txt")]
        )
        #expect(merged.map(\.displayName) == ["a.txt", "new.txt"])
    }

    @Test("Merging nothing changes nothing")
    func emptyIncomingIsANoOp() {
        let existing = [attachment("a.txt")]
        #expect(AttachmentIntake.merging([], into: existing).map(\.displayName) == ["a.txt"])
    }

    // MARK: - Loading

    /// A scratch directory with real files in it, torn down afterwards.
    private func withScratchFiles(
        _ names: [String],
        _ body: (URL, [URL]) async throws -> Void
    ) async throws {
        let root = URL.temporaryDirectory
            .appendingPathComponent("logue-intake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try names.map { name -> URL in
            let url = root.appendingPathComponent(name)
            try "contents of \(name)".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        try await body(root, urls)
    }

    @Test("Files load in the order they were given")
    func loadPreservesOrder() async throws {
        // The chips read left to right in drop order, so a loader that raced would move a
        // chip out from under the pointer about to close it.
        try await withScratchFiles(["a.txt", "b.txt", "c.txt"]) { _, urls in
            let loaded = await AttachmentIntake.load(urls: urls)
            #expect(loaded.map(\.displayName) == ["a.txt", "b.txt", "c.txt"])
        }
    }

    @Test("One unreadable file does not cost the whole batch")
    func oneBadFileKeepsTheRest() async throws {
        // Attaching four files and getting none because one was a broken alias is worse than
        // attaching three. Note what this pins: every URL yields an attachment today, so the
        // missing file arrives as a chip carrying no text rather than being dropped. Either
        // behaviour satisfies "the rest survive"; silently losing the good files does not.
        try await withScratchFiles(["good1.txt", "good2.txt"]) { root, urls in
            let missing = root.appendingPathComponent("gone.txt")
            let loaded = await AttachmentIntake.load(urls: [urls[0], missing, urls[1]])
            let names = loaded.map(\.displayName)
            #expect(names.contains("good1.txt"))
            #expect(names.contains("good2.txt"))
        }
    }

    @Test("Nothing in, nothing out")
    func loadingNoURLsIsEmpty() async {
        #expect(await AttachmentIntake.load(urls: []).isEmpty)
    }

    // MARK: - The picker allowlist

    @Test("Every Office type resolves, so the allowlist never silently widens")
    func officeTypesResolve() {
        // Each is written `UTType("org.openxmlformats…") ?? .data`. If an identifier is wrong
        // — or an OS release stops vending it — the fallback does not fail closed, it widens
        // the picker to *every* file type. The user then picks a .zip, the loader stages a
        // chip carrying nothing, and the file appears to have been ignored with no error.
        for identifier in [
            "org.openxmlformats.spreadsheetml.sheet",
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.presentationml.presentation",
        ] {
            #expect(UTType(identifier) != nil, "no UTType for \(identifier)")
        }
        #expect(AttachmentIntake.acceptedTypes.contains(.data) == false, "the allowlist degraded to .data")
    }
}
