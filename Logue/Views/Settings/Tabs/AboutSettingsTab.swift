import Sparkle
import SwiftUI

/// A SwiftUI view that wraps Sparkle's `SPUUpdater.checkForUpdates()` as a button action.
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates") {
            checkForUpdatesViewModel.checkForUpdates()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

/// View model that observes the Sparkle updater's `canCheckForUpdates` property.
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

struct AboutSettingsTab: View {
    private let updater: SPUUpdater?
    private let navigator = SettingsNavigator.shared

    init(updater: SPUUpdater?) {
        self.updater = updater
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App branding
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppThemeConstants.accent)
                    .accessibilityHidden(true)

                Text("Logue")
                    .font(.title.bold())

                Text("Version \(currentAppVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Private AI meeting & writing assistant.\nAll inference runs locally — no network required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Spacer().frame(height: 28)

            // Update section
            VStack(spacing: 10) {
                Divider()
                    .padding(.horizontal, 40)

                if let updater {
                    CheckForUpdatesView(updater: updater)
                        .padding(.top, 8)
                } else {
                    Text("Update checking unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard navigator.pendingCheckForUpdates, let updater else { return }
            navigator.pendingCheckForUpdates = false
            updater.checkForUpdates()
        }
    }
}
