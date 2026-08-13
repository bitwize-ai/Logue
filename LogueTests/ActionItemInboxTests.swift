import Foundation
@testable import Logue
import Testing

@Suite("ActionItemInbox")
struct ActionItemInboxTests {
    /// An action item written before the dismissed flag existed must still decode.
    @Test("Action items from older builds decode with isDismissed false")
    func decodesLegacyActionItemWithoutDismissedKey() throws {
        let json = """
        {
          "id": "8B1F2C9E-4A6D-4E1B-9C3A-2F5D7E8A1B4C",
          "title": "Send the revised deck",
          "isCompleted": false,
          "createdAt": 776000000
        }
        """
        let data = try #require(json.data(using: .utf8))
        let item = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(item.isDismissed == false)
        #expect(item.title == "Send the revised deck")
    }

    @Test("A dismissed action item round-trips through Codable")
    func dismissedFlagRoundTrips() throws {
        let item = ActionItem(title: "Not a task", isDismissed: true)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ActionItem.self, from: data)
        #expect(decoded.isDismissed)
    }

    // MARK: - Inbox rule

    private var pending: ActionItem { ActionItem(title: "Pending") }
    private var done: ActionItem { ActionItem(title: "Done", isCompleted: true) }
    private var rejected: ActionItem { ActionItem(title: "Rejected", isDismissed: true) }

    @Test("An undecided item is in the inbox")
    func undecidedItemIsInInbox() {
        #expect(ActionItemInbox.matches(pending, mode: .inbox, isPromoted: false))
    }

    @Test("A promoted item leaves the inbox")
    func promotedItemLeavesInbox() {
        #expect(!ActionItemInbox.matches(pending, mode: .inbox, isPromoted: true))
    }

    @Test("A dismissed item leaves the inbox and lands under Dismissed")
    func dismissedItemMovesToDismissed() {
        #expect(!ActionItemInbox.matches(rejected, mode: .inbox, isPromoted: false))
        #expect(ActionItemInbox.matches(rejected, mode: .dismissed, isPromoted: false))
    }

    @Test("A completed item is not awaiting a decision")
    func completedItemLeavesInbox() {
        #expect(!ActionItemInbox.matches(done, mode: .inbox, isPromoted: false))
    }

    @Test("All shows everything regardless of state")
    func allShowsEverything() {
        for item in [pending, done, rejected] {
            #expect(ActionItemInbox.matches(item, mode: .all, isPromoted: false))
        }
        #expect(ActionItemInbox.matches(pending, mode: .all, isPromoted: true))
    }

    @Test("Counts report each chip independently")
    func countsPerMode() {
        let items = [pending, done, rejected]
        let counts = ActionItemInbox.counts(items) { $0.title == "Done" }
        #expect(counts[.inbox] == 1)
        #expect(counts[.dismissed] == 1)
        #expect(counts[.all] == 3)
    }
}
