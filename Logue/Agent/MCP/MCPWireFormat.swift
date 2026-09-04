import Foundation

/// Building MCP requests and reading MCP replies.
///
/// MCP is JSON-RPC 2.0. All of that is parsing, which means all of it can be wrong in ways a
/// running server would not reveal — so it lives here, away from the socket, and is tested
/// against the replies a server can actually send: a good one, an error one, a truncated one,
/// and one that is simply not what it claims to be.
///
/// The parsing is deliberately forgiving about *shape* and strict about *size*. A server that
/// sends an unexpected field should not break discovery; a server that sends a hundred
/// megabytes should not be read at all.
enum MCPWireFormat {
    /// Largest reply we will read, in bytes.
    ///
    /// The output a tool returns is bounded again later by `MCPToolOutput`, but that bound is
    /// applied to a `String` that has already been decoded — so by itself it would let a
    /// server make Logue allocate whatever it sent before anything trimmed it.
    ///
    /// This is the bound in bytes, and it is enforced in two places for two different
    /// reasons. `MCPHTTPTransport` stops *reading* at it, which is what bounds the
    /// allocation; this check stops *parsing* at it, which also covers a caller that got its
    /// bytes some other way. Neither makes the other redundant: reading is where the memory
    /// goes, parsing is where a caller without a socket arrives.
    static let maxResponseBytes = 2 * 1024 * 1024

    /// Longest a server's tool list may be.
    ///
    /// A server offering ten thousand tools would fill the model's context with descriptions
    /// before the user's question got anywhere near it.
    static let maxToolsPerServer = 100

    enum WireError: Error, Equatable {
        case tooLarge
        case notJSON
        case server(String)
        case missingResult
    }

    // MARK: - Requests

    static func listToolsBody() -> Data {
        body(method: "tools/list", params: [:])
    }

    static func callToolBody(name: String, arguments: [String: Any]) -> Data {
        body(method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    private static func body(method: String, params: [String: Any]) -> Data {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            // A constant rather than a counter: each call is its own HTTP request and its own
            // response, so there is nothing to correlate across. A counter would be state
            // shared between servers for no benefit.
            "id": 1,
            "method": method,
            "params": params,
        ]
        // A dictionary we built ourselves from validated parts, so a failure here would be a
        // programming error rather than anything a server did.
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    // MARK: - Replies

    /// The `result` object of a JSON-RPC reply, or the error the server reported.
    static func result(from data: Data) throws -> [String: Any] {
        guard data.count <= maxResponseBytes else { throw WireError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any]
        else { throw WireError.notJSON }

        if let error = envelope["error"] as? [String: Any] {
            // The server's own words, bounded — it is third-party text heading for a log and
            // possibly for the user.
            let message = (error["message"] as? String) ?? "unknown error"
            throw WireError.server(String(message.prefix(200)))
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw WireError.missingResult
        }
        return result
    }

    /// The tools a `tools/list` reply describes.
    ///
    /// Anything unreadable is skipped rather than failing the batch: one malformed entry in a
    /// server's list should cost that tool, not every tool it offers.
    static func tools(from result: [String: Any]) -> [MCPToolDescriptor] {
        let raw = (result["tools"] as? [[String: Any]]) ?? []
        return raw.prefix(maxToolsPerServer).compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            let annotations = entry["annotations"] as? [String: Any] ?? [:]
            return MCPToolDescriptor(
                name: name,
                description: (entry["description"] as? String) ?? "",
                readOnlyHint: (annotations["readOnlyHint"] as? Bool) ?? false,
                destructiveHint: (annotations["destructiveHint"] as? Bool) ?? false
            )
        }
    }

    /// The text a `tools/call` reply returned.
    ///
    /// MCP returns content as a list of typed parts. Only text is read; an image or an
    /// embedded resource is named rather than decoded, because the agent loop feeds this
    /// straight into a prompt and a base64 blob there is a context window spent on nothing.
    static func callText(from result: [String: Any]) -> String {
        let content = (result["content"] as? [[String: Any]]) ?? []
        let parts = content.map { part -> String in
            switch part["type"] as? String {
            case "text": (part["text"] as? String) ?? ""
            case let other?: "[\(other) content omitted]"
            case nil: ""
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
