import Foundation
import Testing

@testable import Logue

/// What you can do with an assistant's answer.
///
/// `copyToClipboard` and `exportMarkdown` are `NSPasteboard`/`NSSavePanel` and are not
/// reachable headlessly. `saveAsNote` is, and it is the one carrying a contract the commit
/// that introduced it relies on: it returns the new document's id so a caller can tick the
/// row it came from. Nothing pinned that.
@Suite("MessageActions")
@MainActor
struct MessageActionsTests {
    @Test("Saving a note writes the text and returns that document's id")
    func saveAsNoteReturnsTheDocumentItWrote() {
        // The island marks the message it saved by pairing this id against the row. If
        // `createDocument` and `updateDocument` ever disagreed about identity, the wrong row
        // would tick — or none would — and nothing would fail.
        let body = "The answer was 41, plus one."
        let id = MessageActions.saveAsNote(body, title: "Saved answer")

        let saved = DocumentStore.shared.documents.first { $0.id == id }
        #expect(saved != nil, "the returned id must name a document that exists")
        #expect(saved?.body == body, "the update has to have been applied before the id is handed back")
        #expect(saved?.title == "Saved answer")

        DocumentStore.shared.deleteDocument(id: id)
    }

    @Test("Two saves make two documents")
    func eachSaveIsItsOwnDocument() {
        // Saving the same answer twice is a slip the app should not silently collapse — the
        // user asked for two notes and would go looking for the second one.
        let first = MessageActions.saveAsNote("same text", title: "A")
        let second = MessageActions.saveAsNote("same text", title: "A")
        #expect(first != second)

        DocumentStore.shared.deleteDocument(id: first)
        DocumentStore.shared.deleteDocument(id: second)
    }

    @Test("An empty answer still produces a document rather than nothing")
    func emptyBodyStillSaves() {
        // The button is only offered on a settled, non-empty message, so this is defensive —
        // but returning an id for a document that was never created would be the worst
        // possible failure, since the caller ticks a row on the strength of it.
        let id = MessageActions.saveAsNote("", title: "Empty")
        #expect(DocumentStore.shared.documents.contains { $0.id == id })
        DocumentStore.shared.deleteDocument(id: id)
    }
}
