import Foundation

/// A tool as a server describes itself.
///
/// Everything in here is the server's word. The name it wants, the description it wants the
/// model to read, and its own opinion of how dangerous it is. None of that is taken at face
/// value — see `MCPClearance` for the part that matters.
struct MCPToolDescriptor: Equatable, Sendable {
    /// The name the server publishes. Never used as-is; see `MCPToolNaming`.
    let name: String
    let description: String
    /// MCP's `readOnlyHint` annotation. A hint, from the thing being judged.
    let readOnlyHint: Bool
    /// MCP's `destructiveHint` annotation. Believed when it says yes, never when it says no.
    let destructiveHint: Bool

    init(name: String, description: String, readOnlyHint: Bool = false, destructiveHint: Bool = false) {
        self.name = name
        self.description = description
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
    }
}

/// How much a tool from a server is trusted.
///
/// #63's rule is that a remote tool is not more trusted than a local one. In practice it has
/// to be trusted *less*, and the reason is that the trust decision for a built-in is made by
/// reading its source, while the trust decision for a remote tool would be made by reading
/// what the server says about itself.
///
/// So: **a server's tool is never `.regular`.** MCP servers can annotate a tool `readOnlyHint`
/// and Logue does not act on it, because a server that wants to avoid an approval prompt sets
/// exactly that annotation. The hint is believed in only one direction — a server saying
/// "this is destructive" is taken at its word and raises the bar to Touch ID, because there
/// is no incentive to lie in that direction.
///
/// The asymmetry is the whole design: claims that *reduce* scrutiny are ignored, claims that
/// *increase* it are honoured.
enum MCPClearance {
    static func clearance(for descriptor: MCPToolDescriptor) -> ToolClearance {
        descriptor.destructiveHint ? .dangerous : .sensitive
    }
}
