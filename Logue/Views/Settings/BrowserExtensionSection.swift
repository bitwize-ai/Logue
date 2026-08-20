import SwiftUI

/// The switch for the browser bridge, under Privacy, and the link to the extension itself.
///
/// Under Privacy rather than a general or "integrations" tab because the trade is a privacy one:
/// the bridge is a listening socket that any program running as this user can reach. That is
/// worth saying in the interface rather than only in a commit message, so the copy names the
/// address and says plainly that nothing leaves the Mac.
///
/// It is on by default as of 1.1.0 — see `BrowserBridgeSettings` — so the copy here says when
/// the port is open rather than describing it as something the user has yet to allow.
struct BrowserExtensionSection: View {
    @State private var bridge = BrowserBridgeServer.shared
    /// `@AppStorage` rather than a `@State` snapshot: the latter read the default once at view
    /// init and never again, so anything else toggling the setting would leave this switch
    /// showing the opposite of the truth. The `true` matches what `BrowserBridgeSettings`
    /// registers, so a fresh install does not show "off" while the server is running.
    @AppStorage(AppConstants.UserDefaultsKeys.browserBridgeEnabled) private var isEnabled = true
    @State private var modelManager = ModelManager.shared

    /// Whether answers would be produced by an external provider rather than on this Mac.
    ///
    /// `LLMEngine` prefers its API client when one is configured, so this is not hypothetical:
    /// with a cloud model active, page text sent over the bridge leaves the machine.
    private var usesExternalProvider: Bool {
        modelManager.activeModel?.type == .api
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browser Extension")
                .font(.headline)

            Text("Let the Logue browser extension use this Mac's models — chat and writing tools "
                + "in your browser, answered by whichever model Logue is set to use. "
                + "The extension talks to Logue over your Mac's own loopback address, and the "
                + "reply comes back the same way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(UICopy.WhatsNew.chromeExtensionLink) {
                HelpMenuActions.openChromeExtension()
            }
            .controlSize(.small)

            Toggle("Allow the browser extension to connect", isOn: $isEnabled)
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { _, enabled in
                    BrowserBridgeSettings.isEnabled = enabled
                    bridge.applySetting()
                }

            if isEnabled {
                statusRow
                if usesExternalProvider {
                    externalProviderWarning
                }
            }

            Text("While this is on, Logue accepts connections on 127.0.0.1 — reachable only from "
                + "this Mac, never from the network. Any program running as you can reach it too. "
                + "Logue accepts them by default so the extension works once installed; turn this "
                + "off to close the port, and it stays off.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown only when it is true, because it contradicts what someone reasonably assumes from a
    /// local bridge — and this is the Privacy tab, where the claim has to be exactly right.
    private var externalProviderWarning: some View {
        Label(
            "Your active model is an external provider, so text sent from the browser goes to it "
                + "rather than staying on this Mac. Switch to an on-device model to keep it local.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(AppThemeConstants.warning)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let port = bridge.activePort {
            Label("Listening on 127.0.0.1:\(String(port))", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.success)
        } else if let error = bridge.lastError {
            // Shown rather than logged: a toggle that turned itself on and did nothing is the
            // worst version of this.
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(AppThemeConstants.error)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Starting…", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
