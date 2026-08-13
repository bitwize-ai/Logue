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
}
