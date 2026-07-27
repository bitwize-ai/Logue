import Foundation
@testable import Logue
import Testing

/// Building the graph from real store models, rather than hand-made entries.
@Suite("LinkIndexBuild")
struct LinkIndexBuildTests {
    private func document(_ title: String, _ body: String, trashed: Bool = false) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        doc.isTrashed = trashed
        return doc
    }

    private func meeting(_ title: String, summary: String?) -> MeetingNote {
        var note = MeetingNote()
        note.title = title
        note.summary = summary
        return note
    }

    @Test("A document body link resolves to another document")
    func documentToDocument() {
        let alpha = document("Alpha", "see [[Beta]]")
        let beta = document("Beta", "")
        let index = LinkIndex.build(documents: [alpha, beta], meetings: [])

        #expect(index.outgoing(from: alpha.id) == [beta.id])
        #expect(index.backlinks(to: beta.id) == [alpha.id])
    }

    @Test("A meeting summary link resolves to a document")
    func meetingToDocument() {
        let spec = document("Spec", "")
        let standup = meeting("Standup", summary: "agreed in [[Spec]]")
        let index = LinkIndex.build(documents: [spec], meetings: [standup])

        #expect(index.outgoing(from: standup.id) == [spec.id])
        #expect(index.kind(of: standup.id) == .meeting)
        #expect(index.kind(of: spec.id) == .document)
    }

    @Test("A document can link to a meeting by title")
    func documentToMeeting() {
        let standup = meeting("Standup", summary: nil)
        let notes = document("Notes", "from [[Standup]]")
        let index = LinkIndex.build(documents: [notes], meetings: [standup])

        #expect(index.outgoing(from: notes.id) == [standup.id])
    }

    @Test("A meeting with no summary is still indexed as a link target")
    func meetingWithoutSummaryIsIndexed() {
        let standup = meeting("Standup", summary: nil)
        let notes = document("Notes", "[[Standup]]")
        let index = LinkIndex.build(documents: [notes], meetings: [standup])

        #expect(index.title(of: standup.id) == "Standup")
        #expect(index.backlinks(to: standup.id) == [notes.id])
    }

    @Test("Trashed documents are excluded from the graph entirely")
    func trashedDocumentsExcluded() {
        let alpha = document("Alpha", "[[Beta]]")
        let beta = document("Beta", "", trashed: true)
        let index = LinkIndex.build(documents: [alpha, beta], meetings: [])

        // Beta is neither a resolvable target nor an indexed item.
        #expect(index.outgoing(from: alpha.id).isEmpty)
        #expect(index.title(of: beta.id) == nil)
        #expect(index.brokenTargets(from: alpha.id) == ["Beta"])
    }

    @Test("Building from empty stores yields an empty graph")
    func emptyStores() {
        let index = LinkIndex.build(documents: [], meetings: [])
        #expect(index.linkedItemIDs.isEmpty)
    }

    @Test("Unicode titles resolve across kinds")
    func unicodeAcrossKinds() {
        let review = meeting("会議メモ", summary: nil)
        let notes = document("Notes", "see [[会議メモ]]")
        let index = LinkIndex.build(documents: [notes], meetings: [review])

        #expect(index.outgoing(from: notes.id) == [review.id])
    }
}
