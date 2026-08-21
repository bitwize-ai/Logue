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
    func add(name: String, endpoint: URL) {
        servers.append(MCPServer(name: sanitize(name), endpoint: endpoint))
        persist()
    }

    /// Renames or re-points a server, keeping its identity and its enabled state.
    ///
    /// Deliberately does not touch `isEnabled`: editing an address is not consent to start
    /// talking to the new one, and a server that was off must stay off through an edit.
    func update(id: UUID, name: String, endpoint: URL) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].name = sanitize(name)
        servers[index].endpoint = endpoint
        persist()
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
            return try JSONDecoder().decode([MCPServer].self, from: data)
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
