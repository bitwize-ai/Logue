import Foundation
@testable import Logue
import Testing

/// Bulk operations over a selection, and the capture-then-organise inbox flow.
@Suite("BulkActionsAndInbox")
struct BulkActionInboxTests {
    private func document(
        _ title: String,
        tags: [String] = [],
        organised: Bool? = nil,
        trashed: Bool = false
    ) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = title
        doc.tags = tags
        doc.isTrashed = trashed
        if let organised {
            doc.isOrganised = organised
        }
        return doc
    }

    // MARK: - Bulk tagging

    @Test("Adding a tag applies it to every selected document")
    func bulkAddTag() {
        let documents = [document("A"), document("B")]
        let updated = BulkAction.addingTag("urgent", to: documents)
        let allTagged = updated.allSatisfy { $0.tags.contains("urgent") }
        #expect(allTagged)
    }

    @Test("Adding a tag a document already has does not duplicate it")
    func bulkAddTagNoDuplicate() {
        let updated = BulkAction.addingTag("urgent", to: [document("A", tags: ["urgent"])])
        #expect(updated.first?.tags == ["urgent"])
    }

    @Test("Tag matching when adding is case-insensitive")
    func bulkAddTagCaseInsensitive() {
        let updated = BulkAction.addingTag("Urgent", to: [document("A", tags: ["urgent"])])
        #expect(updated.first?.tags.count == 1)
    }

    @Test("A blank tag is refused")
    func blankTagRefused() {
        let updated = BulkAction.addingTag("   ", to: [document("A")])
        #expect(updated.first?.tags.isEmpty == true)
    }

    @Test("Removing a tag removes it from every selected document")
    func bulkRemoveTag() {
        let updated = BulkAction.removingTag("urgent", from: [document("A", tags: ["urgent", "x"])])
        #expect(updated.first?.tags == ["x"])
    }

    // MARK: - Bulk trash

    @Test("Trashing marks every selected document and stamps the time")
    func bulkTrash() {
        let updated = BulkAction.trashing([document("A"), document("B")])
        let allStamped = updated.allSatisfy { $0.trashedAt != nil }
        let allTrashed = updated.allSatisfy(\.isTrashed)
        #expect(allTrashed)
        #expect(allStamped)
    }

    @Test("Restoring clears the trashed state and stamp")
    func bulkRestore() {
        let trashed = BulkAction.trashing([document("A")])
        let restored = BulkAction.restoring(trashed)
        let noneTrashed = restored.allSatisfy { !$0.isTrashed }
        let noneStamped = restored.allSatisfy { $0.trashedAt == nil }
        #expect(noneTrashed)
        #expect(noneStamped)
    }

    // MARK: - Bulk space move

    @Test("Moving assigns the space to every selected document")
    func bulkMoveToSpace() {
        let spaceID = UUID()
        let updated = BulkAction.moving([document("A"), document("B")], toSpace: spaceID)
        let allMoved = updated.allSatisfy { $0.spaceID == spaceID }
        #expect(allMoved)
    }

    @Test("Moving to nil unfiles the documents")
    func bulkUnfile() {
        let spaceID = UUID()
        let filed = BulkAction.moving([document("A")], toSpace: spaceID)
        let unfiled = BulkAction.moving(filed, toSpace: nil)
        #expect(unfiled.first?.spaceID == nil)
    }

    @Test("An empty selection is handled without error")
    func emptySelection() {
        #expect(BulkAction.addingTag("x", to: []).isEmpty)
        #expect(BulkAction.trashing([]).isEmpty)
    }

    // MARK: - Inbox

    @Test("A new document starts unorganised, so it lands in the inbox")
    func newDocumentIsUnorganised() {
        #expect(WritingDocument().isOrganised == false)
    }

    @Test("Legacy documents are treated as organised so the inbox is not flooded")
    func legacyDocumentsAreOrganised() throws {
        let legacy = """
        {
            "id": "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40",
            "title": "Legacy", "body": "", "goalMode": "casual",
            "createdAt": 0, "modifiedAt": 0, "isFavorited": false,
            "tags": [], "chatMessages": [], "isTrashed": false
        }
        """
        let doc = try JSONDecoder().decode(WritingDocument.self, from: Data(legacy.utf8))
        #expect(doc.isOrganised)
    }

    @Test("Marking organised removes a document from the inbox")
    func markOrganised() {
        var doc = document("A", organised: false)
        doc.isOrganised = true
        #expect(doc.isOrganised)
    }

    @Test("The inbox contains only unorganised, untrashed documents")
    func inboxContents() {
        let documents = [
            document("New", organised: false),
            document("Filed", organised: true),
            document("Deleted", organised: false, trashed: true),
        ]
        let titles = InboxFilter.inbox(from: documents).map(\.title)
        #expect(titles == ["New"])
    }

    @Test("Inbox count matches the inbox contents")
    func inboxCount() {
        let documents = [document("A", organised: false), document("B", organised: true)]
        #expect(InboxFilter.count(in: documents) == 1)
    }

    @Test("Bulk organising empties the inbox")
    func bulkOrganise() {
        let documents = [document("A", organised: false), document("B", organised: false)]
        let updated = BulkAction.markingOrganised(documents)
        #expect(InboxFilter.inbox(from: updated).isEmpty)
    }

    @Test("The next inbox item after one is organised supports auto-advance")
    func nextInboxItem() {
        let first = document("A", organised: false)
        let second = document("B", organised: false)
        let next = InboxFilter.nextItem(after: first.id, in: [first, second])
        #expect(next?.id == second.id)
    }

    @Test("There is no next item when the inbox is exhausted")
    func noNextInboxItem() {
        let only = document("A", organised: false)
        #expect(InboxFilter.nextItem(after: only.id, in: [only]) == nil)
    }
}
