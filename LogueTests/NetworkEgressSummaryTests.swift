import Foundation
import Testing

@testable import Logue

/// Everything that can send data off this Mac, and whether it is on.
///
/// Logue advertises that nothing leaves the laptop by default, and MCP adds a whole new route
/// out. A claim like that is only worth anything if the app can show its working.
@Suite("NetworkEgressSummary")
struct NetworkEgressSummaryTests {
    private func routes(_ inputs: NetworkEgressSummary.Inputs) -> [NetworkEgressSummary.Route] {
        NetworkEgressSummary.routes(for: inputs)
    }

    private func route(_ id: String, _ inputs: NetworkEgressSummary.Inputs) -> NetworkEgressSummary.Route? {
        routes(inputs).first { $0.id == id }
    }

    // MARK: - The default posture

    @Test("Out of the box, nothing optional is sending anything")
    func defaultsAreQuiet() {
        // The claim in the README, asserted. Update checks are the one thing on by default,
        // and they are listed rather than hidden.
        let quiet = NetworkEgressSummary.Inputs(automaticUpdateChecks: false)
        #expect(NetworkEgressSummary.hasActiveEgress(for: quiet) == false)
        #expect(routes(quiet).filter(\.isActive).isEmpty)
    }

    @Test("Every route is named, on or off")
    func everyRouteIsAlwaysListed() {
        // A privacy page that only lists what is currently on is a page that tells you
        // nothing about what could be.
        let ids = Set(routes(NetworkEgressSummary.Inputs()).map(\.id))
        #expect(ids.isSuperset(of: ["mcp", "webSearch", "externalModels", "modelDownloads", "updates"]))
    }

    @Test("Every route says something concrete")
    func everyRouteExplainsItself() {
        for route in routes(NetworkEgressSummary.Inputs()) {
            #expect(route.detail.isEmpty == false)
            #expect(route.detail.contains("may ") == false, "hedging is not a description: \(route.detail)")
        }
    }

    @Test("A route the user cannot refuse is named anyway")
    func mandatoryRoutesAreStillListed() {
        // The difference between a privacy page and a marketing one.
        #expect(route("modelDownloads", NetworkEgressSummary.Inputs())?.isOptional == false)
    }

    // MARK: - MCP

    @Test("Adding a server is not turning it on, and the page says so")
    func addingIsNotEnabling() {
        let detail = route("mcp", NetworkEgressSummary.Inputs())?.detail
        #expect(detail?.contains("does not turn it on") == true)
    }

    @Test("A loopback-only set of servers is not egress")
    func loopbackServersAreNotEgress() {
        // Enabled, listed, and not leaving. Calling this egress makes the real warning
        // easier to ignore.
        let local = NetworkEgressSummary.Inputs(
            enabledMCPServers: ["Local tools"],
            mcpServersLeavingTheMachine: 0,
            automaticUpdateChecks: false
        )
        #expect(route("mcp", local)?.isActive == false)
        #expect(route("mcp", local)?.detail.contains("nothing leaves") == true)
        #expect(NetworkEgressSummary.hasActiveEgress(for: local) == false)
    }

    @Test("A remote server is egress, and is named")
    func remoteServersAreEgress() {
        let remote = NetworkEgressSummary.Inputs(
            enabledMCPServers: ["GitHub"],
            mcpServersLeavingTheMachine: 1
        )
        #expect(route("mcp", remote)?.isActive == true)
        #expect(route("mcp", remote)?.detail.contains("GitHub") == true)
        #expect(NetworkEgressSummary.hasActiveEgress(for: remote))
    }

    @Test("A long list of servers is summarised rather than run on")
    func serverListsAreBounded() {
        let many = NetworkEgressSummary.Inputs(
            enabledMCPServers: ["A", "B", "C", "D", "E"],
            mcpServersLeavingTheMachine: 5
        )
        let detail = try? #require(route("mcp", many)?.detail)
        #expect(detail?.contains("and 2 more") == true)
    }

    // MARK: - The other routes

    @Test("Web search says what goes and what does not")
    func webSearchIsSpecific() {
        let detail = route("webSearch", NetworkEgressSummary.Inputs(webSearchEnabled: true))?.detail
        #expect(detail?.contains("search terms") == true)
        #expect(detail?.contains("rest of the conversation does not") == true)
    }

    @Test("External providers are counted, and silent when there are none")
    func externalProvidersAreCounted() {
        let none = route("externalModels", NetworkEgressSummary.Inputs())
        #expect(none?.isActive == false)
        #expect(none?.detail.contains("nothing is sent") == true)

        let one = route("externalModels", NetworkEgressSummary.Inputs(externalModelCount: 1))
        #expect(one?.isActive == true)
        #expect(one?.detail.contains("1 provider") == true)
    }

    @Test("The browser extension is listed precisely because it sounds like egress")
    func browserExtensionIsListedAsLocal() {
        // People expect a browser extension to be a network feature. It is not one, and
        // saying so plainly is more useful than leaving it off the list.
        let bridge = route("browserBridge", NetworkEgressSummary.Inputs(browserBridgeEnabled: true))
        #expect(bridge?.isActive == false)
        #expect(bridge?.detail.contains("does not leave") == true)
    }

    @Test("Update checks say what they do and do not send")
    func updateChecksAreDescribed() {
        let on = route("updates", NetworkEgressSummary.Inputs(automaticUpdateChecks: true))
        #expect(on?.isActive == true)
        #expect(on?.detail.contains("No account") == true)

        let off = route("updates", NetworkEgressSummary.Inputs(automaticUpdateChecks: false))
        #expect(off?.isActive == false)
    }
}
