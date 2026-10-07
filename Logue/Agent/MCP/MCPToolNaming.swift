import Foundation

/// What a tool from an MCP server is called once it is in Logue's registry.
///
/// The registry is a flat namespace keyed by name: `AgentCoordinator` resolves a call by
/// looking up `registeredTools.first { $0.name == name }`. A server that published a tool
/// called `delete_document` would therefore be *found first or found instead*, depending on
/// ordering — and the model, which only sees names and descriptions, would have no way to
/// tell that the thing deleting the user's documents was a remote server.
///
/// So a server's tools are never registered under the name the server chose. They are
/// prefixed with the server's own namespace, and the prefix is derived rather than supplied:
/// a server cannot pick a namespace that collides with a built-in, because it does not pick
/// one at all.
///
/// Pure, so the collision rules are testable without a network.
enum MCPToolNaming {
    /// Separates the namespace from the tool's own name. Two underscores rather than one
    /// because built-in names already contain single underscores, and a single separator
    /// would make `search__web` and `search_web` a parsing question rather than a lookup.
    static let separator = "__"

    /// Longest a published name may be. Model tool-call schemas are not generous, and a name
    /// truncated by the tokenizer is a tool that can be described but never called.
    static let maxNameLength = 64

    /// The namespace for a server, derived from its name.
    ///
    /// Lowercased, non-alphanumerics collapsed to underscores, and bounded. A server called
    /// "GitHub (work)" publishes under `github_work`.
    static func namespace(for serverName: String) -> String {
        let folded = serverName.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let collapsed = String(folded)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        let bounded = String(collapsed.prefix(24))
        // A server named entirely in punctuation, or in a script with no ASCII letters,
        // still needs somewhere to live. "server" is not reserved by any built-in.
        return bounded.isEmpty ? "server" : bounded
    }

    /// The name a server's tool is registered under.
    static func published(serverName: String, toolName: String) -> String {
        let namespace = namespace(for: serverName)
        let tool = sanitize(toolName)
        let full = namespace + separator + tool
        guard full.count > maxNameLength else { return full }
        // The namespace is what makes the name safe, so the tool's half is what gets cut.
        let room = max(1, maxNameLength - namespace.count - separator.count)
        return namespace + separator + String(tool.prefix(room))
    }

    /// Whether `name` is a name a server published, rather than one of ours.
    ///
    /// Answered by the *shape* of the name rather than by looking the server up, so it stays
    /// true for a call that arrives after its server was removed — which is the property a
    /// caller deciding how much to trust an in-flight call needs.
    ///
    /// Nothing outside this module asks yet. It is here because the shape question has to be
    /// answerable without the store, and getting that wrong later would mean re-deriving it
    /// from a list that no longer contains the server.
    static func isPublished(_ name: String) -> Bool {
        guard let range = name.range(of: separator) else { return false }
        return !name[name.startIndex ..< range.lowerBound].isEmpty
            && range.upperBound < name.endIndex
    }

    /// Splits a published name back into its parts, or `nil` if it is not one.
    static func split(_ name: String) -> (namespace: String, tool: String)? {
        guard let range = name.range(of: separator) else { return nil }
        let namespace = String(name[name.startIndex ..< range.lowerBound])
        let tool = String(name[range.upperBound...])
        guard !namespace.isEmpty, !tool.isEmpty else { return nil }
        return (namespace, tool)
    }

    private static func sanitize(_ toolName: String) -> String {
        let folded = toolName.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let collapsed = String(folded)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return collapsed.isEmpty ? "tool" : collapsed
    }
}
