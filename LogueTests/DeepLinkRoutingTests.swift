import Foundation
@testable import Logue
import Testing

@Suite("DeepLinkRouting")
struct DeepLinkRoutingTests {
    private let identifier = UUID(uuidString: "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40") ?? UUID()

    @Test("A link carries its target identifier in the notification payload")
    func payloadCarriesIdentifier() {
        let payload = DeepLink.document(id: identifier).notificationPayload
        #expect(payload[DeepLink.UserInfoKey.identifier] as? UUID == identifier)
    }

    @Test("Each target maps to a distinct notification name")
    func distinctNotificationNames() {
        let names = Set([
            DeepLink.document(id: identifier).notificationName,
            DeepLink.meeting(id: identifier).notificationName,
            DeepLink.space(id: identifier).notificationName,
        ])
        #expect(names.count == 3)
    }

    @Test("Routing a valid URL posts the matching notification with the identifier")
    func validURLPostsNotification() async throws {
        let url = try #require(URL(string: "logue://document/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))

        var receivedIdentifier: UUID?
        let token = NotificationCenter.default.addObserver(
            forName: DeepLink.document(id: identifier).notificationName,
            object: nil,
            queue: nil
        ) { notification in
            receivedIdentifier = notification.userInfo?[DeepLink.UserInfoKey.identifier] as? UUID
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let handled = DeepLinkRouter.route(url: url)

        #expect(handled)
        #expect(receivedIdentifier == identifier)
    }

    @Test("Routing an unrecognised URL is reported as unhandled")
    func invalidURLIsUnhandled() throws {
        let url = try #require(URL(string: "logue://document/not-a-uuid"))
        #expect(DeepLinkRouter.route(url: url) == false)
    }

    @Test("Routing a foreign scheme is reported as unhandled")
    func foreignSchemeIsUnhandled() throws {
        let url = try #require(URL(string: "https://example.com/document/x"))
        #expect(DeepLinkRouter.route(url: url) == false)
    }
}
