import SwiftUI

/// The callout that introduces the browser extension, on Home for the week after an upgrade.
///
/// It is on Home rather than in Settings because it has something to disclose, not only
/// something to advertise: 1.1.0 turns the loopback bridge on by default, and a socket that
/// starts listening should say so somewhere the user actually goes. So the same card carries
/// three things — what the extension is, the fact that Logue is now listening for it, and the
/// switch to stop.
///
/// `BrowserExtensionPromo` owns when it appears; this only renders it.
struct BrowserExtensionBannerView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.browserExtensionPromoDismissed)
    private var dismissed = false
    /// Stored as a number rather than a `Date` because `@AppStorage` cannot bind to `Date`.
    /// Zero means "never shown", which is also what an absent key reads as.
    @AppStorage(AppConstants.UserDefaultsKeys.browserExtensionPromoFirstShown)
    private var firstShownAt: Double = 0
    @AppStorage(AppConstants.UserDefaultsKeys.browserBridgeEnabled) private var bridgeEnabled = true

    private var firstShown: Date? {
        firstShownAt > 0 ? Date(timeIntervalSince1970: firstShownAt) : nil
    }

    private var isVisible: Bool {
        BrowserExtensionPromo.shouldShow(
            firstShown: firstShown, dismissed: dismissed, now: Date()
        )
    }

    var body: some View {
        if isVisible {
            content
                .task {
                    // Stamped on the first render rather than at launch: the week should start
                    // when the user could actually have seen it, not when the app opened behind
                    // a window they never looked at.
                    if firstShownAt == 0 {
                        firstShownAt = Date().timeIntervalSince1970
                    }
                }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title3)
                .foregroundStyle(AppThemeConstants.brandPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("New: Logue in your browser")
                    .font(.subheadline.weight(.medium))

                Text(bridgeEnabled
                    ? "The Chrome extension brings Logue's chat and writing tools into any tab, "
                    + "answered by the model on this Mac. Logue is listening for it on your Mac's "
                    + "own loopback address — nothing leaves the machine, and you can stop it here."
                    : "The Chrome extension brings Logue's chat and writing tools into any tab, "
                    + "answered by the model on this Mac. It needs Logue to accept its connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(UICopy.WhatsNew.chromeExtensionLink) {
                        HelpMenuActions.openChromeExtension()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // The off switch travels with the disclosure. Sending the user to Settings
                    // to find it would be disclosing the socket and hiding the remedy.
                    Toggle("Accept connections", isOn: $bridgeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption)
                        // `@AppStorage` has already written the setting by the time this
                        // runs; the server still has to be told to start or stop.
                        .onChange(of: bridgeEnabled) { _, _ in
                            BrowserBridgeServer.shared.applySetting()
                        }
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss the browser extension notice")
        }
        .padding(14)
        .background(
            AppThemeConstants.brandPrimary.opacity(AppThemeConstants.hoverOpacity),
            in: RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppThemeConstants.radiusLarge)
                .strokeBorder(
                    AppThemeConstants.brandPrimary.opacity(AppThemeConstants.opacityMedium),
                    lineWidth: 1
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
