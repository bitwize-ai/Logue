import Foundation
import MLXLMCommon

/// How Logue talks to a server.
///
/// A protocol so the tool below can be tested without a socket — every rule that matters
/// (naming, clearance, bounding, failure) is in the adapter, not in the wire format.
protocol MCPTransport: Sendable {
    func listTools(server: MCPServer) async throws -> [MCPToolDescriptor]
    func call(server: MCPServer, tool: String, arguments: [String: Any]) async throws -> String
}

/// A tool a server offers, wearing Logue's `AgentTool` so the rest of the agent cannot tell
/// the difference — which is the point. It goes into the same registry, through the same
/// approval gate, and appears on both surfaces because there is only one pipeline.
///
/// What it does *not* inherit from being a normal tool is trust. Three things are decided
/// here rather than by the server:
///
/// - **Its name.** Namespaced, so it cannot shadow a built-in (`MCPToolNaming`).
/// - **Its clearance.** Never `.regular` (`MCPClearance`).
/// - **What its output may do.** Bounded and delimited (`MCPToolOutput`).
///
/// A failure is returned as a result rather than thrown, so an unreachable server costs the
/// model a tool rather than costing the user their turn.
struct MCPRemoteTool: AgentTool {
    let server: MCPServer
    let descriptor: MCPToolDescriptor
    let transport: any MCPTransport

    var name: String {
        MCPToolNaming.published(serverName: server.name, toolName: descriptor.name)
    }

    /// The server's own description, bounded and flattened.
    ///
    /// It goes into the system prompt, so it is third-party text in an instruction position —
    /// the one place this codebase is most careful about. It cannot be wrapped in delimiters
    /// the way tool *output* is, because the model has to read it as a description; so it is
    /// bounded, stripped of newlines that could fake a section break, and prefixed with where
    /// it came from, so the model is told this text is a server's claim about itself.
    var description: String {
        let claim = descriptor.description
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let bounded = String(claim.prefix(300))
        return "[from the \"\(server.name)\" MCP server] \(bounded)"
    }

    var clearance: ToolClearance {
        MCPClearance.clearance(for: descriptor)
    }

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [:],
            required: []
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        do {
            let raw = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await transport.call(server: server, tool: descriptor.name, arguments: arguments) }
                group.addTask {
                    try await Task.sleep(for: .seconds(MCPTimeout.call))
                    throw MCPCallError.timedOut
                }
                guard let first = try await group.next() else { throw MCPCallError.timedOut }
                group.cancelAll()
                return first
            }
            return MCPToolOutput.prepare(raw)
        } catch {
            // Returned, not thrown: a server that is down should cost the model a tool, not
            // cost the user the turn it was in the middle of.
            return MCPServerHealth.callFailureMessage(
                serverName: server.name,
                reason: reason(for: error)
            )
        }
    }

    /// What to say about a failure.
    ///
    /// Never the URL. A URL in a message is a URL in a log the moment someone pastes it, and
    /// this codebase logs hosts only.
    private func reason(for error: Error) -> String {
        if error is MCPCallError {
            return "it did not respond in time"
        }
        if let wire = error as? MCPWireFormat.WireError {
            switch wire {
            case .tooLarge: return "it sent more than Logue will read"
            case .notJSON, .missingResult: return "its reply could not be understood"
            case let .server(message): return message
            }
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return "the call failed"
    }
}

enum MCPCallError: Error, Equatable {
    case timedOut
}
