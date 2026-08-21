import Foundation
import Testing

@testable import Logue

/// A server arrives switched off, and its address has to be one we are willing to talk to.
///
/// An MCP server is network egress, and Logue's claim is that nothing leaves the laptop
/// unless the user turned it on. These are the cases that make that claim true rather than
/// aspirational.
@Suite("MCPServer")
struct MCPServerTests {
    @Test("A new server is off")
    func newServersAreOff() throws {
        let url = try #require(URL(string: "https://mcp.example.com"))
        #expect(MCPServer(name: "Example", endpoint: url).isEnabled == false)
    }

    @Test("A server restored from a file with no flag is off")
    func decodingWithoutTheFlagIsOff() throws {
        // The migration case. A file written before `isEnabled` existed must not read as a
        // server that is allowed to reach the network — the default has to be the safe one,
        // which is why this is decodeIfPresent with `false` rather than a bare decode.
        let json = """
        {"id": "\(UUID().uuidString)", "name": "Old", "endpoint": "https://mcp.example.com"}
        """
        let server = try JSONDecoder().decode(MCPServer.self, from: Data(json.utf8))
        #expect(server.isEnabled == false)
    }

    @Test("Being on survives a round trip")
    func enabledRoundTrips() throws {
        // The other half: the safe default must not also mean the user's choice is forgotten
        // every launch.
        let url = try #require(URL(string: "https://mcp.example.com"))
        let server = MCPServer(name: "Example", endpoint: url, isEnabled: true)
        let decoded = try JSONDecoder().decode(
            MCPServer.self,
            from: JSONEncoder().encode(server)
        )
        #expect(decoded == server)
    }
}

@Suite("MCPEndpoint")
struct MCPEndpointTests {
    private func accepted(_ raw: String) -> Bool {
        if case .success = MCPEndpoint.validate(raw) { return true }
        return false
    }

    @Test("HTTPS is accepted")
    func httpsIsFine() {
        #expect(accepted("https://mcp.example.com"))
        #expect(accepted("https://mcp.example.com:8443/sse"))
    }

    @Test("Plain HTTP off the machine is refused")
    func remoteHTTPIsRefused() {
        // The project rule: HTTPS for every user-supplied endpoint except loopback.
        #expect(accepted("http://mcp.example.com") == false)
        if case let .failure(reason) = MCPEndpoint.validate("http://mcp.example.com") {
            #expect(reason == .insecureScheme("http"))
        } else {
            Issue.record("expected a rejection")
        }
    }

    @Test("Plain HTTP on this machine is allowed")
    func loopbackHTTPIsAllowed() {
        // MCP servers are very often run locally, and refusing them would push people towards
        // turning the check off rather than meeting it. Loopback never leaves the machine, so
        // the encryption requirement buys nothing there.
        #expect(accepted("http://localhost:3000"))
        #expect(accepted("http://127.0.0.1:3000/sse"))
        #expect(accepted("http://[::1]:3000"))
    }

    @Test("A host that merely looks local is not local")
    func lookalikeHostsAreNotLoopback() {
        // `localhost.example.com` is somebody else's machine, and prefix matching is how that
        // gets treated as this one.
        #expect(accepted("http://localhost.example.com") == false)
        #expect(accepted("http://notlocalhost") == false)
        #expect(accepted("http://127.0.0.1.example.com") == false)
    }

    @Test("Other schemes are refused")
    func otherSchemesAreRefused() {
        #expect(accepted("ftp://mcp.example.com") == false)
        #expect(accepted("file:///etc/passwd") == false)
        #expect(accepted("javascript:alert(1)") == false)
    }

    @Test("Nothing, and nonsense, are refused with the right reason")
    func emptyAndGarbageAreRefused() {
        #expect(MCPEndpoint.validate("") == .failure(.empty))
        #expect(MCPEndpoint.validate("   ") == .failure(.empty))
        #expect(accepted("https://") == false)
    }

    @Test("Only a non-local address counts as leaving the machine")
    func egressIsNamedAccurately() throws {
        // Drives what the Privacy tab says. Calling a loopback server "egress" makes the
        // warning that does matter easier to ignore.
        #expect(MCPEndpoint.leavesTheMachine(try #require(URL(string: "https://mcp.example.com"))))
        #expect(MCPEndpoint.leavesTheMachine(try #require(URL(string: "http://localhost:3000"))) == false)
        #expect(MCPEndpoint.leavesTheMachine(try #require(URL(string: "http://127.0.0.1:1234"))) == false)
    }
}

/// What a server's tools are called once they are in Logue's registry.
@Suite("MCPToolNaming")
struct MCPToolNamingTests {
    @Test("No server can shadow a built-in tool")
    @MainActor
    func serversCannotShadowBuiltIns() {
        // The attack this prevents, walked against the real registry: the registry is a flat
        // namespace resolved by `first { $0.name == name }`, so a server publishing
        // `delete_document` would be found first or instead depending on ordering — and the
        // model, which sees only names and descriptions, could not tell the difference.
        let builtIns = Set(AgentCoordinator.allKnownTools().map(\.name))
        #expect(builtIns.isEmpty == false, "an empty registry would make this prove nothing")

        for builtIn in builtIns {
            for serverName in ["Evil", "delete", "", "built_in", builtIn] {
                let published = MCPToolNaming.published(serverName: serverName, toolName: builtIn)
                #expect(builtIns.contains(published) == false, "\(serverName) shadowed \(builtIn)")
            }
        }
    }

    @Test("A published name carries its server")
    func namesAreNamespaced() {
        #expect(MCPToolNaming.published(serverName: "GitHub", toolName: "create_issue") == "github__create_issue")
    }

    @Test("A server name is folded into something usable")
    func namespacesAreFolded() {
        #expect(MCPToolNaming.namespace(for: "GitHub (work)") == "github_work")
        #expect(MCPToolNaming.namespace(for: "  spaced  out  ") == "spaced_out")
        #expect(MCPToolNaming.namespace(for: "!!!") == "server", "a name with nothing usable still gets a home")
        #expect(MCPToolNaming.namespace(for: "") == "server")
    }

    @Test("A published name is bounded")
    func namesAreBounded() {
        // A name the tokenizer truncates is a tool that can be described but never called.
        let published = MCPToolNaming.published(
            serverName: String(repeating: "server", count: 20),
            toolName: String(repeating: "tool", count: 40)
        )
        #expect(published.count <= MCPToolNaming.maxNameLength)
        #expect(published.contains(MCPToolNaming.separator), "the namespace survives the cut")
    }

    @Test("Published names are told apart from ours by shape alone")
    func publishedNamesAreRecognisable() {
        // Asked by the approval gate, so it has to stay true for a call that arrives after
        // its server was removed — which rules out answering by looking the server up.
        #expect(MCPToolNaming.isPublished("github__create_issue"))
        #expect(MCPToolNaming.isPublished("delete_document") == false)
        #expect(MCPToolNaming.isPublished("semantic_search_meetings") == false)
        #expect(MCPToolNaming.isPublished("__leading") == false)
        #expect(MCPToolNaming.isPublished("trailing__") == false)
    }

    @Test("A published name splits back into its parts")
    func namesSplit() {
        let parts = MCPToolNaming.split("github__create_issue")
        #expect(parts?.namespace == "github")
        #expect(parts?.tool == "create_issue")
        #expect(MCPToolNaming.split("delete_document") == nil)
    }
}
