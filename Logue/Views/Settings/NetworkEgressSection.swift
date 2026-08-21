import SwiftUI

/// What leaves this Mac, listed rather than summarised.
///
/// The Privacy tab described encryption, storage and permissions but said nothing about the
/// network — which was defensible while almost nothing reached it. MCP servers change that,
/// and a new egress route in an app that advertises having almost none has to be visible in
/// the place people go to check.
///
/// Every route is listed whether it is on or off. A page that shows only what is currently
/// active tells you nothing about what could be, and the routes nobody can refuse are named
/// too — that is the difference between a privacy page and a marketing one.
struct NetworkEgressSection: View {
    @State private var mcpServers = MCPServerStore.shared

    @AppStorage(AppConstants.UserDefaultsKeys.webSearchEnabled)
    private var webSearchEnabled: Bool = false
    @AppStorage(AppConstants.UserDefaultsKeys.browserBridgeEnabled)
    private var browserBridgeEnabled: Bool = true

    private var inputs: NetworkEgressSummary.Inputs {
        let enabled = mcpServers.enabledServers
        return NetworkEgressSummary.Inputs(
            webSearchEnabled: webSearchEnabled,
            browserBridgeEnabled: browserBridgeEnabled,
            externalModelCount: 0,
            enabledMCPServers: enabled.map(\.name),
            mcpServersLeavingTheMachine: enabled.count { MCPEndpoint.leavesTheMachine($0.endpoint) },
            automaticUpdateChecks: true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("What leaves this Mac")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(NetworkEgressSummary.hasActiveEgress(for: inputs) ? "Some routes are on" : "Nothing is being sent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(NetworkEgressSummary.routes(for: inputs)) { route in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(route.isActive ? AppThemeConstants.brandPrimary : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(route.name)
                                .font(.callout)
                            if !route.isOptional {
                                Text("always")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            }
                        }
                        Text(route.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(route.name), \(route.isActive ? "active" : "not active")")
                .accessibilityValue(route.detail)
            }
        }
    }
}
