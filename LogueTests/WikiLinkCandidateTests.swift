import Foundation
@testable import Logue
import Testing

/// Ranking and filtering the titles offered for an in-progress `[[` link.
@Suite("WikiLinkCandidates")
struct WikiLinkCandidateTests {
    private func document(_ title: String, trashed: Bool = false) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.isTrashed = trashed
        return doc
    }

    private func meeting(_ title: String) -> MeetingNote {
        var note = MeetingNote()
        note.title = title
        return note
    }

    @Test("An empty query offers every candidate")
    func emptyQueryOffersAll() {
        let candidates = WikiLinkCandidates.matching(
            query: "",
            documents: [document("Alpha"), document("Beta")],
            meetings: [meeting("Standup")],
            excluding: nil
        )
        #expect(candidates.count == 3)
    }

    @Test("Candidates are filtered by the query")
    func filtersByQuery() {
        let candidates = WikiLinkCandidates.matching(
            query: "alp",
            documents: [document("Alpha"), document("Beta")],
            meetings: [],
            excluding: nil
        )
        #expect(candidates.map(\.title) == ["Alpha"])
    }

    @Test("Documents and meetings are both offered, and tagged by kind")
    func bothKindsOffered() {
        let candidates = WikiLinkCandidates.matching(
            query: "s",
            documents: [document("Spec")],
            meetings: [meeting("Standup")],
            excluding: nil
        )
        #expect(Set(candidates.map(\.kind)) == [.document, .meeting])
    }

    @Test("Trashed documents are never offered")
    func trashedExcluded() {
        let candidates = WikiLinkCandidates.matching(
            query: "",
            documents: [document("Alpha"), document("Gone", trashed: true)],
            meetings: [],
            excluding: nil
        )
        #expect(candidates.map(\.title) == ["Alpha"])
    }

    @Test("The document being edited is not offered as a link to itself")
    func excludesSelf() {
        let alpha = document("Alpha")
        let candidates = WikiLinkCandidates.matching(
            query: "",
            documents: [alpha, document("Beta")],
            meetings: [],
            excluding: alpha.id
        )
        #expect(candidates.map(\.title) == ["Beta"])
    }

    @Test("Untitled candidates are skipped — an empty target is not a usable link")
    func skipsEmptyTitles() {
        let candidates = WikiLinkCandidates.matching(
            query: "",
            documents: [document("   "), document("Alpha")],
            meetings: [],
            excluding: nil
        )
        #expect(candidates.map(\.title) == ["Alpha"])
    }

    @Test("A non-matching query offers nothing")
    func noMatches() {
        let candidates = WikiLinkCandidates.matching(
            query: "zzz",
            documents: [document("Alpha")],
            meetings: [],
            excluding: nil
        )
        #expect(candidates.isEmpty)
    }

    @Test("A unicode query matches a unicode title")
    func unicodeQuery() {
        let candidates = WikiLinkCandidates.matching(
            query: "会議",
            documents: [document("会議メモ"), document("Alpha")],
            meetings: [],
            excluding: nil
        )
        #expect(candidates.map(\.title) == ["会議メモ"])
    }

    @Test("Results are capped so the menu stays usable")
    func resultsCapped() {
        let many = (0 ..< 200).map { document("Item \($0)") }
        let candidates = WikiLinkCandidates.matching(
            query: "item",
            documents: many,
            meetings: [],
            excluding: nil
        )
        #expect(candidates.count <= WikiLinkCandidates.maxResults)
    }
}
