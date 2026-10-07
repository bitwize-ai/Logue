import Foundation

/// Which of a user's MCP tools may be offered to the model right now.
///
/// Four separate gates, and the order they are applied in is not arbitrary — each one is a
/// different person's decision and a later gate must never re-open an earlier one:
///
/// 1. **The server is enabled.** The user's decision, and the only one that authorises
///    network egress at all.
/// 2. **The server is not known to be down.** Logue's observation, not a permission.
/// 3. **The tool is not on the disable list.** The user's decision again, per tool, and the
///    same list that turns off built-ins — a remote tool is not exempt from it.
/// 4. **Nothing collides.** Two servers can publish the same namespaced name if the user
///    names them alike, and a flat registry cannot hold both.
///
/// Free of networking and of the store, so the matrix is testable directly.
enum MCPRegistryPlan {
    /// One tool that will be registered.
    struct Publication: Equatable {
        let server: MCPServer
        let descriptor: MCPToolDescriptor
        /// The name it will occupy in the registry.
        let publishedName: String
    }

    /// - Parameters:
    ///   - servers: every server the user has, enabled or not.
    ///   - discovered: what each server last said it offers, keyed by server id.
    ///   - health: what is known about each server, keyed by server id. A server missing
    ///     from this map has not been contacted, which is not the same as being down.
    ///   - disabledToolNames: the per-tool disable list, in published-name form.
    static func publications(
        servers: [MCPServer],
        discovered: [UUID: [MCPToolDescriptor]],
        health: [UUID: MCPServerHealth.State],
        disabledToolNames: Set<String>
    ) -> [Publication] {
        var claimed: Set<String> = []
        var result: [Publication] = []

        for server in servers {
            // 1. Only the user can authorise a server to run.
            guard server.isEnabled else { continue }
            // 2. A server known to be down offers nothing. Absent means not yet contacted,
            //    which still offers — see `MCPServerHealth.State.offersTools`.
            guard (health[server.id] ?? .unknown).offersTools else { continue }

            for descriptor in discovered[server.id] ?? [] {
                let name = MCPToolNaming.published(serverName: server.name, toolName: descriptor.name)
                // 3. The same list that turns off built-ins.
                guard !disabledToolNames.contains(name) else { continue }
                // 4. First claim wins, deterministically, because `servers` is ordered.
                guard claimed.insert(name).inserted else { continue }
                result.append(Publication(server: server, descriptor: descriptor, publishedName: name))
            }
        }
        return result
    }
}
