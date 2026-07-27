import Foundation
@testable import Logue
import Testing

/// Resolving a wikilink target or deep link to the item it refers to.
@Suite("ContentNavigator")
struct ContentNavigatorTests {
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

    @Test("A document title resolves to that document")
    func resolvesDocument() {
        let alpha = document("Alpha")
        let target = ContentNavigator.resolve(
            target: "Alpha", documents: [alpha], meetings: []
        )
        #expect(target == .document(id: alpha.id))
    }

    @Test("A meeting title resolves to that meeting")
    func resolvesMeeting() {
        let standup = meeting("Standup")
        let target = ContentNavigator.resolve(
            target: "Standup", documents: [], meetings: [standup]
        )
        #expect(target == .meeting(id: standup.id))
    }

    @Test("Resolution is case-insensitive and ignores surrounding whitespace")
    func caseAndWhitespaceInsensitive() {
        let alpha = document("Alpha")
        let target = ContentNavigator.resolve(
            target: "  alpha  ", documents: [alpha], meetings: []
        )
        #expect(target == .document(id: alpha.id))
    }

    @Test("Wikilink syntax around the target is tolerated")
    func acceptsWikilinkSyntax() {
        let alpha = document("Alpha")
        let target = ContentNavigator.resolve(
            target: "[[Alpha]]", documents: [alpha], meetings: []
        )
        #expect(target == .document(id: alpha.id))
    }

    @Test("An alias resolves on its target, not its display text")
    func aliasResolvesOnTarget() {
        let alpha = document("Alpha")
        let target = ContentNavigator.resolve(
            target: "[[Alpha|call it anything]]", documents: [alpha], meetings: []
        )
        #expect(target == .document(id: alpha.id))
    }

    @Test("An unknown title resolves to nothing")
    func unknownTitle() {
        #expect(ContentNavigator.resolve(target: "Nowhere", documents: [], meetings: []) == nil)
    }

    @Test("An empty target resolves to nothing")
    func emptyTarget() {
        #expect(ContentNavigator.resolve(target: "   ", documents: [], meetings: []) == nil)
    }

    @Test("A trashed document is not a navigation target")
    func trashedNotResolved() {
        let gone = document("Gone", trashed: true)
        #expect(ContentNavigator.resolve(target: "Gone", documents: [gone], meetings: []) == nil)
    }

    @Test("A documents wins over a meeting with the same title, deterministically")
    func documentWinsOnTitleCollision() {
        let alpha = document("Same")
        let clash = meeting("Same")
        let target = ContentNavigator.resolve(
            target: "Same", documents: [alpha], meetings: [clash]
        )
        #expect(target == .document(id: alpha.id))
    }

    @Test("A unicode title resolves")
    func unicodeTitle() {
        let notes = document("会議メモ")
        let target = ContentNavigator.resolve(
            target: "会議メモ", documents: [notes], meetings: []
        )
        #expect(target == .document(id: notes.id))
    }

    @Test("A deep link maps to the same navigation target type")
    func deepLinkMapsToTarget() {
        let identifier = UUID()
        #expect(ContentNavigator.target(for: .document(id: identifier)) == .document(id: identifier))
        #expect(ContentNavigator.target(for: .meeting(id: identifier)) == .meeting(id: identifier))
        #expect(ContentNavigator.target(for: .space(id: identifier)) == .space(id: identifier))
    }
}
