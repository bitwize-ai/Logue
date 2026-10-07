import Foundation

/// Everything that can send data off this Mac, and whether it is on right now.
///
/// Logue's claim is that nothing leaves the laptop by default. A claim like that is only
/// worth anything if the app can *show* it — so this enumerates every route out, including
/// the ones that are always on, and says which are currently active.
///
/// MCP servers are what forced the issue: adding a whole new egress route to an app that
/// advertises having almost none means the Privacy tab has to stop being a paragraph and
/// start being a list. But the honest version of that list includes the routes that were
/// already there, or it is a list designed to make the newest thing look isolated.
///
/// Pure, so the wording and the on/off logic are testable without any of the services.
enum NetworkEgressSummary {
    struct Route: Identifiable, Equatable {
        let id: String
        /// What the user turns on or off, in their words.
        let name: String
        /// What actually leaves, stated concretely. Not "may transmit data".
        let detail: String
        /// Whether anything is going out this way right now.
        let isActive: Bool
        /// Whether the user can turn it off. A route they cannot refuse has to be named
        /// anyway — that is the difference between a privacy page and a marketing one.
        let isOptional: Bool
    }

    /// What the summary needs to know, gathered by the caller.
    struct Inputs {
        var webSearchEnabled: Bool
        var browserBridgeEnabled: Bool
        var externalModelCount: Int
        var enabledMCPServers: [String]
        var mcpServersLeavingTheMachine: Int
        var automaticUpdateChecks: Bool

        init(
            webSearchEnabled: Bool = false,
            browserBridgeEnabled: Bool = false,
            externalModelCount: Int = 0,
            enabledMCPServers: [String] = [],
            mcpServersLeavingTheMachine: Int = 0,
            automaticUpdateChecks: Bool = true
        ) {
            self.webSearchEnabled = webSearchEnabled
            self.browserBridgeEnabled = browserBridgeEnabled
            self.externalModelCount = externalModelCount
            self.enabledMCPServers = enabledMCPServers
            self.mcpServersLeavingTheMachine = mcpServersLeavingTheMachine
            self.automaticUpdateChecks = automaticUpdateChecks
        }
    }

    static func routes(for inputs: Inputs) -> [Route] {
        [
            Route(
                id: "mcp",
                name: "MCP servers",
                detail: mcpDetail(for: inputs),
                // A loopback server is an integration worth listing and is not egress, so it
                // does not light this up — calling it egress makes the real warning easier
                // to ignore.
                isActive: inputs.mcpServersLeavingTheMachine > 0,
                isOptional: true
            ),
            Route(
                id: "webSearch",
                name: "Web search",
                detail: "Your search terms, and the pages the agent opens, go to the search "
                    + "provider. The rest of the conversation does not.",
                isActive: inputs.webSearchEnabled,
                isOptional: true
            ),
            Route(
                id: "externalModels",
                name: "External AI providers",
                detail: inputs.externalModelCount > 0
                    ? "\(inputs.externalModelCount) provider\(inputs.externalModelCount == 1 ? "" : "s") "
                    + "configured. Anything you send to one of these models leaves this Mac."
                    : "None configured. On-device models are used, and nothing is sent.",
                isActive: inputs.externalModelCount > 0,
                isOptional: true
            ),
            Route(
                id: "browserBridge",
                name: "Browser extension",
                detail: "The extension talks to Logue over a local connection on this Mac. "
                    + "Page content does not leave it.",
                // Named because people expect a browser extension to be a network feature.
                // It is not one, and saying so plainly is more useful than omitting it.
                isActive: false,
                isOptional: true
            ),
            Route(
                id: "modelDownloads",
                name: "Model downloads",
                detail: "Downloading a model fetches it from Hugging Face. Nothing about you "
                    + "is sent — only which model you asked for.",
                isActive: false,
                isOptional: false
            ),
            Route(
                id: "updates",
                name: "Update checks",
                detail: inputs.automaticUpdateChecks
                    ? "Logue asks GitHub whether a newer version exists. No account, no "
                    + "identifier, no contents."
                    : "Turned off. Logue will not check for updates.",
                isActive: inputs.automaticUpdateChecks,
                isOptional: true
            ),
        ]
    }

    /// Whether anything at all is currently leaving the machine.
    static func hasActiveEgress(for inputs: Inputs) -> Bool {
        routes(for: inputs).contains { $0.isActive && $0.isOptional }
    }

    private static func mcpDetail(for inputs: Inputs) -> String {
        guard !inputs.enabledMCPServers.isEmpty else {
            return "None enabled. Adding a server does not turn it on."
        }
        let named = inputs.enabledMCPServers.prefix(3).joined(separator: ", ")
        let rest = inputs.enabledMCPServers.count - min(3, inputs.enabledMCPServers.count)
        let list = rest > 0 ? "\(named) and \(rest) more" : named
        guard inputs.mcpServersLeavingTheMachine > 0 else {
            return "\(list). All on this Mac, so nothing leaves it."
        }
        return "\(list). Tool calls, and whatever the agent passes as arguments, go to "
            + "\(inputs.mcpServersLeavingTheMachine) server\(inputs.mcpServersLeavingTheMachine == 1 ? "" : "s") off this Mac."
    }
}
