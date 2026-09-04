import Foundation
import os.log

/// What each server last said it offers, and whether it answered.
///
/// The registry asks this for tools on every rebuild, so it holds the last known answer
/// rather than going to the network — a rebuild happens on every send, and a send must not
/// wait on someone else's server before the model sees a tool list.
///
/// **`refresh()` and `forget(id:)` have no caller yet, and that is the current state of the
/// feature rather than an oversight.** Both belong to the Settings screen that adds, enables
/// and removes servers, which is the one remaining box of #63. Until it lands there is no way
/// to add a server, `discovered` stays empty, and no MCP tool is ever published — which is
/// why this half could land without being able to reach the network at all.
@MainActor
@Observable
final class MCPCatalog {
    static let shared = MCPCatalog()

    private(set) var discovered: [UUID: [MCPToolDescriptor]] = [:]
    private(set) var health: [UUID: MCPServerHealth.State] = [:]

    private let store: MCPServerStore
    private let transport: any MCPTransport
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MCP")

    init(store: MCPServerStore = .shared, transport: any MCPTransport = MCPHTTPTransport()) {
        self.store = store
        self.transport = transport
    }

    /// The tools to hand the registry.
    ///
    /// Every gate lives in `MCPRegistryPlan`, which is pure; this only supplies what it needs
    /// and turns the answer into tools.
    func tools(disabledToolNames: Set<String>) -> [any AgentTool] {
        MCPRegistryPlan.publications(
            servers: store.servers,
            discovered: discovered,
            health: health,
            disabledToolNames: disabledToolNames
        )
        .map { publication in
            MCPRemoteTool(
                server: publication.server,
                descriptor: publication.descriptor,
                transport: transport
            )
        }
    }

    /// Asks every enabled server what it can do.
    ///
    /// Failure is per-server: one server being down must not stop the others being
    /// discovered, which is why each is its own task and its own recorded state.
    func refresh() async {
        await withTaskGroup(of: (UUID, Result<[MCPToolDescriptor], any Error>).self) { group in
            for server in store.enabledServers {
                group.addTask { [transport] in
                    do {
                        return try await (server.id, .success(transport.listTools(server: server)))
                    } catch {
                        return (server.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                // The server list is read again here, not only when the group was built. A
                // refresh takes as long as the slowest server, and the user can remove one
                // while it runs — `forget(id:)` would clear its entries and this loop would
                // then write them straight back, for a server that no longer exists. Nothing
                // would offer those tools, because `MCPRegistryPlan` walks the store, but
                // they would be held for the rest of the session.
                guard store.servers.contains(where: { $0.id == id }) else { continue }

                switch result {
                case let .success(descriptors):
                    discovered[id] = descriptors
                    health[id] = .reachable(toolCount: descriptors.count)
                case let .failure(error):
                    // The tool list is kept. A server that is down now may be back before the
                    // next send, and re-discovering from nothing would mean a flap costs the
                    // user every tool until a refresh completes. `MCPRegistryPlan` already
                    // refuses to publish while the state is `.unreachable`.
                    health[id] = .unreachable(reason: Self.reason(for: error))
                    // Host only, never the address — see the project logging rule.
                    logger.error(
                        "MCP server unreachable: \(self.store.servers.first { $0.id == id }?.endpoint.host ?? "?", privacy: .public)"
                    )
                }
            }
        }
    }

    /// Forgets a server entirely. Called when the user removes one.
    func forget(id: UUID) {
        discovered[id] = nil
        health[id] = nil
    }

    private static func reason(for error: Error) -> String {
        if error is MCPCallError {
            return "It did not respond in time."
        }
        if let wire = error as? MCPWireFormat.WireError {
            switch wire {
            case .tooLarge: return "It sent more than Logue will read."
            case .notJSON, .missingResult: return "Its reply could not be understood."
            case let .server(message): return message
            }
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return "It could not be reached."
    }
}
