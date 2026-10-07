import Foundation
import Testing

@testable import Logue

/// Which of a user's MCP tools may be offered to the model.
///
/// Four gates, each a different person's decision, and a later one must never re-open an
/// earlier one. That is what these cases are for.
@Suite("MCPRegistryPlan")
struct MCPRegistryPlanTests {
    private func server(_ name: String, enabled: Bool = true, id: UUID = .init()) throws -> MCPServer {
        MCPServer(
            id: id,
            name: name,
            endpoint: try #require(URL(string: "https://mcp.example.com")),
            isEnabled: enabled
        )
    }

    private func descriptor(_ name: String) -> MCPToolDescriptor {
        MCPToolDescriptor(name: name, description: "")
    }

    private func plan(
        servers: [MCPServer],
        discovered: [UUID: [MCPToolDescriptor]],
        health: [UUID: MCPServerHealth.State] = [:],
        disabled: Set<String> = []
    ) -> [MCPRegistryPlan.Publication] {
        MCPRegistryPlan.publications(
            servers: servers,
            discovered: discovered,
            health: health,
            disabledToolNames: disabled
        )
    }

    // MARK: - Gate 1: the user enabled the server

    @Test("A disabled server publishes nothing, however many tools it offers")
    func disabledServersPublishNothing() throws {
        // The only gate that authorises network egress at all. A tool list cached from when
        // the server was on must not survive the user turning it off.
        let off = try server("GitHub", enabled: false)
        #expect(plan(servers: [off], discovered: [off.id: [descriptor("create_issue")]]).isEmpty)
    }

    @Test("An enabled server publishes its tools")
    func enabledServersPublish() throws {
        let on = try server("GitHub")
        let published = plan(servers: [on], discovered: [on.id: [descriptor("create_issue")]])
        #expect(published.map(\.publishedName) == ["github__create_issue"])
    }

    // MARK: - Gate 2: it is not known to be down

    @Test("A server known to be down publishes nothing")
    func unreachableServersPublishNothing() throws {
        let on = try server("GitHub")
        let result = plan(
            servers: [on],
            discovered: [on.id: [descriptor("create_issue")]],
            health: [on.id: .unreachable(reason: "timed out")]
        )
        #expect(result.isEmpty)
    }

    @Test("A server not yet contacted still publishes")
    func uncontactedServersStillPublish() throws {
        // Absent from the health map means "not contacted", which is not "down". Treating
        // the two the same would mean the first message of every launch has no MCP tools.
        let on = try server("GitHub")
        #expect(plan(servers: [on], discovered: [on.id: [descriptor("x")]]).count == 1)
    }

    // MARK: - Gate 3: the per-tool disable list

    @Test("A remote tool is not exempt from the disable list")
    func disableListAppliesToRemoteTools() throws {
        // The same list that turns off built-ins. "I never want the agent to do X" has to
        // mean the same thing whoever supplies X.
        let on = try server("GitHub")
        let result = plan(
            servers: [on],
            discovered: [on.id: [descriptor("create_issue"), descriptor("close_issue")]],
            disabled: ["github__create_issue"]
        )
        #expect(result.map(\.publishedName) == ["github__close_issue"])
    }

    @Test("The disable list is matched on the published name, not the server's")
    func disableListMatchesPublishedNames() throws {
        // What the user turned off in Settings is what they saw there, which is the
        // namespaced name. Matching the server's raw name would let one server's entry
        // silently disable another's identically-named tool.
        let on = try server("GitHub")
        let result = plan(
            servers: [on],
            discovered: [on.id: [descriptor("create_issue")]],
            disabled: ["create_issue"]
        )
        #expect(result.count == 1, "the built-in-shaped name must not match a namespaced tool")
    }

    // MARK: - Gate 4: collisions

    @Test("Two servers that fold to one namespace cannot both take a name")
    func collisionsAreResolvedDeterministically() throws {
        // Two differently-spelled names can fold to one namespace — "GitHub" and "GITHUB!"
        // both become `github` — and a flat registry cannot hold two tools with one name.
        // First in the list wins, and the list is ordered, so the answer does not change
        // between renders.
        //
        // Note the pair: `git.hub` would *not* collide, because the dot becomes a separator
        // and it folds to `git_hub`. Picking that pair is how this case passes vacuously.
        let first = try server("GitHub")
        let second = try server("GITHUB!")
        let result = plan(
            servers: [first, second],
            discovered: [
                first.id: [descriptor("create_issue")],
                second.id: [descriptor("create_issue")],
            ]
        )
        #expect(result.count == 1)
        #expect(result.first?.server.id == first.id, "the earlier server keeps the name")
    }

    @Test("A collision only costs the colliding tool")
    func collisionsDoNotDropTheWholeServer() throws {
        let first = try server("GitHub")
        let second = try server("GitHub")
        let result = plan(
            servers: [first, second],
            discovered: [
                first.id: [descriptor("create_issue")],
                second.id: [descriptor("create_issue"), descriptor("list_repos")],
            ]
        )
        #expect(result.count == 2)
        #expect(result.map(\.publishedName).contains("github__list_repos"))
    }

    // MARK: - Nothing at all

    @Test("No servers means no publications")
    func emptyIsEmpty() {
        #expect(plan(servers: [], discovered: [:]).isEmpty)
    }

    @Test("A server with no discovered tools publishes nothing")
    func noToolsMeansNoPublications() throws {
        let on = try server("GitHub")
        #expect(plan(servers: [on], discovered: [:]).isEmpty)
    }
}
