import Foundation
@testable import Logue
import Testing

/// What quick-open offers, as opposed to how it ranks it — `QuickOpenTests` covers the matcher.
///
/// These are the rules the palette itself used to hold inline, where nothing could reach them:
/// trashed items stay out, an untitled item is still findable, and the order handed to the
/// matcher is recency.
@Suite("QuickOpenCandidates")
struct QuickOpenCandidateTests {
    private func document(
        _ title: String,
        modified: TimeInterval,
        trashed: Bool = false
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.modifiedAt = Date(timeIntervalSince1970: modified)
        doc.isTrashed = trashed
        return doc
    }

    private func meeting(
        _ title: String,
        modified: TimeInterval,
        trashed: Bool = false
    ) -> MeetingNote {
        MeetingNote(
            title: title,
            modifiedAt: Date(timeIntervalSince1970: modified),
            isTrashed: trashed
        )
    }

    @Test("Documents and meetings both become candidates")
    func bothKindsIncluded() {
        let candidates = QuickOpenItem.candidates(
            documents: [document("Roadmap", modified: 10)],
            meetings: [meeting("Standup", modified: 20)]
        )

        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.title == "Roadmap" && $0.kind == .document })
        #expect(candidates.contains { $0.title == "Standup" && $0.kind == .meeting })
    }

    @Test("Trashed documents are excluded")
    func trashedDocumentsExcluded() {
        let candidates = QuickOpenItem.candidates(
            documents: [
                document("Kept", modified: 10),
                document("Deleted", modified: 20, trashed: true),
            ],
            meetings: []
        )

        #expect(candidates.map(\.title) == ["Kept"])
    }

    @Test("Trashed meetings are excluded")
    func trashedMeetingsExcluded() {
        let candidates = QuickOpenItem.candidates(
            documents: [],
            meetings: [
                meeting("Kept", modified: 10),
                meeting("Deleted", modified: 20, trashed: true),
            ]
        )

        #expect(candidates.map(\.title) == ["Kept"])
    }

    /// Recency is not cosmetic: `QuickOpenMatcher` is stable within a rank, so this order is
    /// what decides which of two equally good matches the user sees first.
    @Test("Candidates are ordered most recently modified first, across both kinds")
    func orderedByRecency() {
        let candidates = QuickOpenItem.candidates(
            documents: [
                document("Oldest", modified: 10),
                document("Newest", modified: 40),
            ],
            meetings: [
                meeting("Middle", modified: 20),
                meeting("Second newest", modified: 30),
            ]
        )

        #expect(candidates.map(\.title) == ["Newest", "Second newest", "Middle", "Oldest"])
    }

    /// The interleaving matters — a naive "documents then meetings" concatenation would pass the
    /// per-kind tests above and still put a stale document above a fresh meeting.
    @Test("A recent meeting outranks an older document")
    func kindsAreInterleavedByDate() {
        let candidates = QuickOpenItem.candidates(
            documents: [document("Old doc", modified: 10)],
            meetings: [meeting("New meeting", modified: 99)]
        )

        #expect(candidates.first?.title == "New meeting")
    }

    @Test("An untitled document still has something to match against")
    func untitledDocumentGetsDefaultTitle() {
        let candidates = QuickOpenItem.candidates(documents: [document("", modified: 10)], meetings: [])
        #expect(candidates.first?.title == AppConstants.defaultDocumentTitle)
    }

    @Test("An untitled meeting still has something to match against")
    func untitledMeetingGetsDefaultTitle() {
        let candidates = QuickOpenItem.candidates(documents: [], meetings: [meeting("", modified: 10)])
        #expect(candidates.first?.title == AppConstants.defaultMeetingTitle)
    }

    @Test("An empty library produces no candidates")
    func emptyLibrary() {
        #expect(QuickOpenItem.candidates(documents: [], meetings: []).isEmpty)
    }

    @Test("A library of only trashed items produces no candidates")
    func onlyTrashed() {
        let candidates = QuickOpenItem.candidates(
            documents: [document("Gone", modified: 10, trashed: true)],
            meetings: [meeting("Also gone", modified: 20, trashed: true)]
        )
        #expect(candidates.isEmpty)
    }

    @Test("Candidate IDs are the underlying item IDs, so selection can open them")
    func idsArePreserved() {
        let doc = document("Roadmap", modified: 10)
        let note = meeting("Standup", modified: 20)
        let candidates = QuickOpenItem.candidates(documents: [doc], meetings: [note])

        #expect(candidates.first(where: { $0.kind == .document })?.id == doc.id)
        #expect(candidates.first(where: { $0.kind == .meeting })?.id == note.id)
    }

    /// The end-to-end shape the palette relies on: build, then rank, and the trashed item must
    /// not come back at the matcher stage either.
    @Test("Matching runs over the candidate list without reviving trashed items")
    func matcherOverCandidates() {
        let candidates = QuickOpenItem.candidates(
            documents: [
                document("Product Roadmap", modified: 30),
                document("Product Retro", modified: 20, trashed: true),
            ],
            meetings: [meeting("Product Review", modified: 10)]
        )
        let results = QuickOpenMatcher.match(query: "prod", in: candidates)

        #expect(results.map(\.title) == ["Product Roadmap", "Product Review"])
    }
}
