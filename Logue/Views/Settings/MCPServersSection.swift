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
    /// How many refreshes are in flight, rather than whether one is.
    ///
    /// Enabling two servers in quick succession starts two, and with a boolean the first to
    /// finish clears the spinner while the second is still going — so the row that has not
    /// been contacted yet looks settled. A count only reaches zero when the last one ends.
    @State private var refreshesInFlight = 0
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if store.servers.isEmpty, !isAdding {
                empty
            } else {
                ForEach(store.servers) { server in
                    // The form replaces the row it is editing, rather than the row vanishing
                    // and a form appearing under the whole list — with several servers, that
                    // leaves no way to tell which one is being edited.
                    if editingID == server.id {
                        form
                    } else {
                        row(for: server)
                    }
                }
            }

            if isAdding {
                form
            } else if editingID == nil {
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
                if refreshesInFlight > 0 {
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

    private func row(for server: MCPServer) -> some View {
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
                Text(displayName(of: server))
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

            // Named for the row they belong to. With several servers, a list of buttons all
            // announcing "Edit" tells a VoiceOver user which action but not which server —
            // and Remove is the one where guessing is expensive.
            Button("Edit") { beginEditing(server) }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Edit \(displayName(of: server))")
            Button("Remove") { remove(server) }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(AppThemeConstants.error)
                .accessibilityLabel("Remove \(displayName(of: server))")
        }
        .padding(.vertical, 4)
    }

    /// What to call a server on screen.
    ///
    /// A name can be empty — the decoder defaults it to `""` so a file written before the
    /// field existed still reads — and a row labelled with nothing is a row that cannot be
    /// told apart from the next one, in the list and in VoiceOver alike.
    private func displayName(of server: MCPServer) -> String {
        server.name.isEmpty ? "Unnamed server" : server.name
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

            if let clash = namespaceClash {
                Text(
                    "“\(clash)” already publishes its tools under the same prefix. "
                        + "Whichever comes first keeps the names; the other's tools are dropped."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if saveFailed {
                Text("That server could not be saved. Check the address.")
                    .font(.caption)
                    .foregroundStyle(AppThemeConstants.error)
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

    /// Another server whose name folds to the same namespace as the one being typed.
    ///
    /// Not blocked — two servers may legitimately be called similar things — but said, because
    /// the consequence is otherwise invisible. The rule is `MCPNamespaceClash`'s; this only
    /// supplies the names, and excludes the server being edited, which cannot clash with
    /// itself.
    private var namespaceClash: String? {
        MCPNamespaceClash.first(
            for: draftName,
            among: store.servers.filter { $0.id != editingID }.map(\.name)
        )
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
        saveFailed = false
    }

    private func commit() {
        guard let url = validatedAddress else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)

        // The store validates too, and its answer is the one that decides. Taking it rather
        // than discarding it is the difference between a refusal the user can see and a
        // button that closes the form, clears the fields and saves nothing — the two
        // validators agree today, and the day one of them gains a rule the other has not,
        // this is what stops that becoming a silent loss of what they typed.
        var saved = false
        if let editingID, let existing = store.servers.first(where: { $0.id == editingID }) {
            // Before the store forgets the old name: what the user turned off is keyed on the
            // published name, which is derived from it. See `MCPRenameMigration`.
            migrateDisabledTools(from: existing.name, to: name)
            saved = store.update(id: editingID, name: name, endpoint: url)
        } else {
            saved = store.add(name: name, endpoint: url)
        }

        guard saved else {
            saveFailed = true
            return
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
        refreshesInFlight += 1
        // `defer` rather than a line after the await: the task is cancelled when this section
        // goes away mid-refresh, and a counter left above zero by a cancellation would leave
        // the spinner turning for the rest of the session.
        defer { refreshesInFlight -= 1 }
        await catalog.refresh()
    }
}
