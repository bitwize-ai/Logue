import Foundation
import Testing

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
}
