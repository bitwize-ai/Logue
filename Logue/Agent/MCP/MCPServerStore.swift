import Foundation
import os.log

/// The servers the user has added, and whether each is allowed to run.
///
/// `UserDefaults` rather than the Keychain: a server's name, address and on/off state are
/// configuration, not secrets, and the project rule is that only secrets go in the Keychain.
/// If per-server credentials are added later they go in the Keychain and this stays where it
/// is — the two have different lifetimes and different failure modes.
///
/// Injectable defaults so the rules are testable against a scratch suite rather than the
/// user's own settings.
@MainActor
@Observable
final class MCPServerStore {
    static let shared = MCPServerStore()

    private(set) var servers: [MCPServer] = []

    private let defaults: UserDefaults
    private let key: String
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "MCP")

    init(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.mcpServers
    ) {
        self.defaults = defaults
        self.key = key
        servers = Self.load(from: defaults, key: key, logger: logger)
    }

    // MARK: - Reading

    /// The servers whose tools may be offered to the model.
    ///
    /// The only thing the registry is allowed to consult. Reading `servers` there would
    /// register a disabled server's tools, which is the one mistake this whole feature cannot
    /// afford to make.
    var enabledServers: [MCPServer] {
        servers.filter(\.isEnabled)
    }

    /// Whether anything is currently permitted to leave the machine.
    ///
    /// Drives the Privacy tab. A loopback server is enabled but is not egress.
    var hasNetworkEgress: Bool {
        enabledServers.contains { MCPEndpoint.leavesTheMachine($0.endpoint) }
    }

    // MARK: - Writing

    /// Adds a server. New servers are disabled — see `MCPServer`.
    ///
    /// Returns false, and stores nothing, if the address does not meet `MCPEndpoint`'s rule.
    @discardableResult
    func add(name: String, endpoint: URL) -> Bool {
        guard isAcceptable(endpoint) else { return false }
        servers.append(MCPServer(name: sanitize(name), endpoint: endpoint))
        persist()
        return true
    }

    /// Renames or re-points a server, keeping its identity and its enabled state.
    ///
    /// Deliberately does not touch `isEnabled`: editing an address is not consent to start
    /// talking to the new one, and a server that was off must stay off through an edit.
    ///
    /// A rejected address changes nothing at all — in particular it does not leave the server
    /// pointing at half an edit, with the new name and the old address.
    @discardableResult
    func update(id: UUID, name: String, endpoint: URL) -> Bool {
        guard isAcceptable(endpoint) else { return false }
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return false }
        servers[index].name = sanitize(name)
        servers[index].endpoint = endpoint
        persist()
        return true
    }

    /// The endpoint rule, applied where the decision is actually made.
    ///
    /// `MCPEndpoint.validate` existed and had no caller outside the tests: the HTTPS-except-
    /// loopback rule was going to be enforced by a Settings field that has not been written
    /// yet. A rule that lives only in a view is a rule the next caller does not get — the same
    /// reason `AskRouter` is a pure function rather than a decision inside a `View` — and here
    /// the next caller is whatever eventually adds a server programmatically.
    ///
    /// The address is never logged whole; the host only, per the project rule.
    private func isAcceptable(_ endpoint: URL) -> Bool {
        if case let .failure(rejection) = MCPEndpoint.validate(endpoint.absoluteString) {
            logger.error(
                "Refused an MCP endpoint on host \(endpoint.host ?? "none", privacy: .public): \(rejection.message, privacy: .public)"
            )
            return false
        }
        return true
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].isEnabled = isEnabled
        persist()
    }

    func remove(id: UUID) {
        servers.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(servers), forKey: key)
        } catch {
            // Never silent: the user's list would look saved and come back empty next launch.
            logger.error("Could not save MCP servers: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String, logger: Logger) -> [MCPServer] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let stored = try JSONDecoder().decode([MCPServer].self, from: data)
            // Re-checked on the way in, not merely on the way out. Everything else in this
            // feature is built on the endpoint rule holding, and a stored list is the one
            // route into it that no UI ever touched: a defaults file written by hand, synced
            // from another machine, or restored from a backup would otherwise hand us an
            // enabled server on plaintext `http://` that every later stage trusts.
            let (acceptable, refused) = stored.reduce(into: ([MCPServer](), 0)) { result, server in
                if case .success = MCPEndpoint.validate(server.endpoint.absoluteString) {
                    result.0.append(server)
                } else {
                    result.1 += 1
                }
            }
            if refused > 0 {
                logger.error("Dropped \(refused, privacy: .public) stored MCP server(s) whose address is not allowed")
            }
            return acceptable
        } catch {
            // Answering with an empty list is the safe failure: no servers means no egress.
            // Losing the list is recoverable by re-adding; silently enabling something we
            // could not read is not.
            logger.error("Could not read MCP servers: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// A server's name reaches the model as part of every tool name it publishes, and reaches
    /// the approval card as text. Bounded and stripped on the way in, once.
    private func sanitize(_ name: String) -> String {
        String(name.prefix(60))
            .filter { !$0.isNewline && $0.asciiValue != 0 }
            .trimmingCharacters(in: .whitespaces)
    }
}
