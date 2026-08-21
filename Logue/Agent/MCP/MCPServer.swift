import Foundation

/// One MCP server the user has added.
///
/// An MCP server is **network egress**, which is the whole reason this type is careful.
/// Logue's stated posture is that nothing leaves the laptop unless the user turned it on, so
/// a server arrives disabled and stays disabled until someone says otherwise — `isEnabled`
/// defaults to `false` on both the memberwise initialiser and the decoder, so neither a new
/// server nor one restored from a file written before the field existed can start out talking
/// to anything.
struct MCPServer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// What the user calls it. Also the namespace its tools are published under.
    var name: String
    /// Where it lives. Validated by `MCPEndpoint` before it is ever stored.
    var endpoint: URL
    /// Off until the user turns it on. See the note above — this default is load-bearing.
    var isEnabled: Bool

    init(id: UUID = .init(), name: String, endpoint: URL, isEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, endpoint, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        endpoint = try container.decode(URL.self, forKey: .endpoint)
        // Absent means off. A file written before this field existed must not read as a
        // server that is allowed to reach the network.
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

/// Whether an address is one we are willing to talk to, and what to say when it is not.
///
/// Split from the model so the rules can be tested without constructing a server, and so the
/// Settings field can validate as the user types rather than at save time.
enum MCPEndpoint {
    enum Rejection: Error, Equatable {
        case empty
        case notAURL
        case insecureScheme(String)
        case missingHost

        var message: String {
            switch self {
            case .empty: "Enter the server's address."
            case .notAURL: "That is not a valid address."
            case let .insecureScheme(scheme):
                "\(scheme) is not encrypted. Use https, or a server on this machine."
            case .missingHost: "That address has no host."
            }
        }
    }

    /// Hosts that may be reached over plain HTTP.
    ///
    /// A server on the loopback interface never leaves the machine, which is the one case
    /// where the encryption requirement buys nothing — and MCP servers are very often run
    /// locally, so refusing them would push people towards disabling the check rather than
    /// meeting it.
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    static func validate(_ raw: String) -> Result<URL, Rejection> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .failure(.notAURL)
        }
        guard let host = url.host, !host.isEmpty else { return .failure(.missingHost) }

        if scheme == "https" {
            return .success(url)
        }
        if scheme == "http", isLocal(host: host) {
            return .success(url)
        }
        return .failure(.insecureScheme(scheme))
    }

    /// Whether talking to this address means data leaving the machine.
    ///
    /// Drives what the Privacy tab says. A loopback server is still an integration the user
    /// should see listed, but it is not egress, and calling it egress makes the warning that
    /// does matter easier to ignore.
    static func leavesTheMachine(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        return !isLocal(host: host)
    }

    /// `URL.host` strips the brackets from an IPv6 literal, so `[::1]` arrives as `::1`;
    /// both spellings are checked because the string the user typed carries them.
    private static func isLocal(host: String) -> Bool {
        let bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return localHosts.contains(bare)
    }
}
