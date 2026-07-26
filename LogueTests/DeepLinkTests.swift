import Foundation
@testable import Logue
import Testing

/// Deep links arrive from outside the app, so parsing is an untrusted-input
/// boundary. Anything unrecognised must resolve to nil rather than a wrong target.
@Suite("DeepLink")
struct DeepLinkTests {
    private let docID = UUID(uuidString: "0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40") ?? UUID()

    @Test("A document link resolves to the document target")
    func parsesDocumentLink() throws {
        let url = try #require(URL(string: "logue://document/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == .document(id: docID))
    }

    @Test("A meeting link resolves to the meeting target")
    func parsesMeetingLink() throws {
        let url = try #require(URL(string: "logue://meeting/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == .meeting(id: docID))
    }

    @Test("A space link resolves to the space target")
    func parsesSpaceLink() throws {
        let url = try #require(URL(string: "logue://space/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == .space(id: docID))
    }

    @Test("Host matching is case-insensitive")
    func hostIsCaseInsensitive() throws {
        let url = try #require(URL(string: "logue://DOCUMENT/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == .document(id: docID))
    }

    @Test("A foreign scheme is rejected")
    func rejectsForeignScheme() throws {
        let url = try #require(URL(string: "https://document/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test("An unknown host is rejected")
    func rejectsUnknownHost() throws {
        let url = try #require(URL(string: "logue://wat/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test("A malformed identifier is rejected")
    func rejectsMalformedIdentifier() throws {
        let url = try #require(URL(string: "logue://document/not-a-uuid"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test("A missing identifier is rejected")
    func rejectsMissingIdentifier() throws {
        let url = try #require(URL(string: "logue://document"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test("Path traversal in the identifier is rejected")
    func rejectsPathTraversal() throws {
        let url = try #require(URL(string: "logue://document/../../etc/passwd"))
        #expect(DeepLink(url: url) == nil)
    }

    @Test("Extra path components are rejected rather than ignored")
    func rejectsExtraPathComponents() throws {
        let url = try #require(
            URL(string: "logue://document/0A47D3B4-3B4E-4A2E-9C1D-2F8A1B6C5D40/extra")
        )
        #expect(DeepLink(url: url) == nil)
    }

    @Test("A link round-trips through its URL representation")
    func roundTripsThroughURL() {
        let link = DeepLink.document(id: docID)
        #expect(DeepLink(url: link.url) == link)
    }
}
