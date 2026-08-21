import Foundation

/// What Logue currently knows about a server, and what that means for its tools.
///
/// #63's rule: failure is visible and local. An unreachable server must disable its tools and
/// say so, rather than failing a turn — because the alternative is that the model calls a
/// tool, the call times out, and the user's question comes back as an error about a server
/// they added last month and had forgotten about.
///
/// Free of networking so the state machine can be tested without one.
enum MCPServerHealth {
    enum State: Equatable {
        /// Not contacted yet this launch.
        case unknown
        /// Answered, and offered this many tools.
        case reachable(toolCount: Int)
        /// Did not answer. Carries what to tell the user.
        case unreachable(reason: String)

        /// Whether this server's tools may be offered to the model.
        ///
        /// `unknown` is included deliberately: a server that has not been contacted yet still
        /// has tools worth registering from its last known list, and refusing to register
        /// until a probe succeeds would mean the first message of every launch has no MCP
        /// tools at all. Being *registered* is not being *reachable* — a call that fails
        /// still fails locally and visibly.
        var offersTools: Bool {
            switch self {
            case .unknown, .reachable: true
            case .unreachable: false
            }
        }

        /// What Settings shows next to the server.
        var summary: String {
            switch self {
            case .unknown: "Not contacted yet"
            case let .reachable(count): "\(count) tool\(count == 1 ? "" : "s")"
            case let .unreachable(reason): reason
            }
        }

        var needsAttention: Bool {
            if case .unreachable = self {
                return true
            }
            return false
        }
    }

    /// What to say when a call to a server fails.
    ///
    /// Returned to the model as the tool's result rather than thrown, so the turn continues:
    /// the model can tell the user it could not reach the server, or answer another way. A
    /// thrown error would end the turn and lose whatever the agent had already worked out.
    ///
    /// The server's *name* is used rather than its address, because a URL in a message is a
    /// URL in a log the moment someone pastes it, and the project rule is that URLs are never
    /// logged whole.
    static func callFailureMessage(serverName: String, reason: String) -> String {
        "Could not reach the \"\(serverName)\" server: \(reason). Its tools are unavailable "
            + "until it responds. Answer without them, and tell the user the server is unreachable."
    }
}
