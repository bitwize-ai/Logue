import Foundation

/// Talking to a server over HTTP.
///
/// Not implemented yet — the wire format is the last piece of #63 and deliberately the last,
/// because every rule that decides whether a call is *allowed* is already settled and tested
/// without it. Until then this reports every server as unreachable, which is the same path a
/// genuinely-down server takes: no tools published, said plainly in Settings, and no turn
/// lost.
struct MCPHTTPTransport: MCPTransport {
    func listTools(server _: MCPServer) async throws -> [MCPToolDescriptor] {
        throw MCPCallError.notImplemented
    }

    func call(server _: MCPServer, tool _: String, arguments _: [String: Any]) async throws -> String {
        throw MCPCallError.notImplemented
    }
}
