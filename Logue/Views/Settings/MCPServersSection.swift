import SwiftUI

/// Adding, enabling, editing and removing the user's MCP servers.
///
/// The rules this screen obeys are not its own — they live in `MCPServerStore`,
/// `MCPEndpoint` and `MCPRegistryPlan`, and were settled and tested before there was a
/// screen. What this file is responsible for is not *undoing* any of them:
///
/// - **Adding is not enabling.** A new server arrives off. Turning it on is a separate,
///   deliberate act, because that is the act authorising network egress.
/// - **An edit changes neither direction of the switch.** Re-pointing a server is not consent
///   to start talking to the new address, and it is not a reason to stop talking to one the
///   user deliberately turned on.
/// - **The address is validated before it is saved**, and the field says why while the user is
///   still typing. `MCPEndpoint.validate` returns the message; this does not write its own.
///   It is *not* the only check — the store refuses a bad address too — and it must not become
///   so again, which is how the rule ended up enforced by nothing.
struct MCPServersSection: View {
    @State private var store = MCPServerStore.shared
    @State private var catalog = MCPCatalog.shared

    @AppStorage(AppConstants.UserDefaultsKeys.disabledAgentTools)
    private var disabledToolsRaw: String = ""

    @State private var isAdding = false
    @State private var editingID: UUID?
    @State private var draftName = ""
    @State private var draftAddress = ""
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if store.servers.isEmpty, !isAdding {
                empty
            } else {
                ForEach(store.servers) { server in
                    row(for: server)
                }
            }

            if isAdding || editingID != nil {
                form
            } else {
                Button("Add a server…") { beginAdding() }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .task { await refresh() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("MCP servers").font(.headline)
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            Text(
                "Servers you add can give the agent extra tools. A server is off until you turn "
                    + "it on, and its tools are approved the same way Logue's own are."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            // Said once, plainly, where the switches are — rather than only on the Privacy
            // tab, which is not where someone is when they turn one on.
            if store.hasNetworkEgress {
                Label(
                    "One or more enabled servers are not on this Mac. Their tools send data over the network.",
                    systemImage: "network"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
    }

    private var empty: some View {
        Text("No servers yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - A server

    @ViewBuilder
    private func row(for server: MCPServer) -> some View {
        if editingID == server.id {
            EmptyView()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Toggle(
                    isOn: Binding(
                        get: { server.isEnabled },
                        set: { enable($0, for: server) }
                    )
                ) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("\(server.name) enabled")

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name.isEmpty ? "Unnamed server" : server.name)
                        .font(.callout)
                    HStack(spacing: 6) {
                        // Shown to the user in full — it is their own address and they need to
                        // recognise it. It is never *logged*; that is the rule, and it is a
                        // different one.
                        Text(server.endpoint.absoluteString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !MCPEndpoint.leavesTheMachine(server.endpoint) {
                            Text("on this Mac")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(status(for: server).summary)
                        .font(.caption2)
                        .foregroundStyle(status(for: server).needsAttention ? AppThemeConstants.error : .secondary)
                }

                Spacer()

                Button("Edit") { beginEditing(server) }
                    .buttonStyle(.link)
                    .font(.caption)
                Button("Remove") { remove(server) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.error)
            }
            .padding(.vertical, 4)
        }
    }

    /// A server nobody has contacted has not failed — see `MCPServerHealth.State`.
    private func status(for server: MCPServer) -> MCPServerHealth.State {
        catalog.health[server.id] ?? .unknown
    }

    // MARK: - The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            TextField("https://example.com/mcp", text: $draftAddress)
                .textFieldStyle(.roundedBorder)

            // While typing, not at save time. The message is `MCPEndpoint`'s so the field and
            // the store cannot disagree about what is allowed.
            if let rejection = liveRejection {
                Text(rejection.message)
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.error)
            } else if let url = validatedAddress, !MCPEndpoint.leavesTheMachine(url) {
                Text("On this Mac, so nothing leaves it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { cancel() }
                Button(editingID == nil ? "Add" : "Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
            }
        }
        .padding(.vertical, 4)
    }

    /// `nil` while the field is empty — an untouched field is not an error.
    private var liveRejection: MCPEndpoint.Rejection? {
        guard !draftAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if case let .failure(rejection) = MCPEndpoint.validate(draftAddress) {
            return rejection
        }
        return nil
    }

    private var validatedAddress: URL? {
        if case let .success(url) = MCPEndpoint.validate(draftAddress) {
            return url
        }
        return nil
    }

    private var canCommit: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty && validatedAddress != nil
    }

    // MARK: - Doing things

    private func beginAdding() {
        editingID = nil
        draftName = ""
        draftAddress = ""
        isAdding = true
    }

    private func beginEditing(_ server: MCPServer) {
        isAdding = false
        draftName = server.name
        draftAddress = server.endpoint.absoluteString
        editingID = server.id
    }

    private func cancel() {
        isAdding = false
        editingID = nil
        draftName = ""
        draftAddress = ""
    }

    private func commit() {
        guard let url = validatedAddress else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)

        if let editingID, let existing = store.servers.first(where: { $0.id == editingID }) {
            // Before the store forgets the old name: what the user turned off is keyed on the
            // published name, which is derived from it. See `MCPRenameMigration`.
            migrateDisabledTools(from: existing.name, to: name)
            store.update(id: editingID, name: name, endpoint: url)
        } else {
            store.add(name: name, endpoint: url)
        }
        cancel()
        Task { await refresh() }
    }

    private func remove(_ server: MCPServer) {
        store.remove(id: server.id)
        // Otherwise the server's last known tool list and health outlive it. Nothing offers
        // them — `MCPRegistryPlan` walks the store — but they are held for a server that no
        // longer exists, and would be read by anything that consults the catalog directly.
        catalog.forget(id: server.id)
    }

    private func enable(_ isEnabled: Bool, for server: MCPServer) {
        store.setEnabled(isEnabled, for: server.id)
        // A server that has just been switched on has no tool list yet, so without this it is
        // enabled and offers nothing until something else happens to refresh.
        Task { await refresh() }
    }

    private func migrateDisabledTools(from oldName: String, to newName: String) {
        let current = Set(
            disabledToolsRaw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let migrated = MCPRenameMigration.remapped(disabled: current, from: oldName, to: newName)
        guard migrated != current else { return }
        disabledToolsRaw = migrated.sorted().joined(separator: ",")
    }

    private func refresh() async {
        isRefreshing = true
        await catalog.refresh()
        isRefreshing = false
    }
}
