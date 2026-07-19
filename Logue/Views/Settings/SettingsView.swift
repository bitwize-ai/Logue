import Sparkle
import SwiftUI

/// App settings window with tabbed configuration panels.
struct SettingsView: View {
    @Environment(ModelManager.self) private var modelManager
    @State private var selectedTab: SettingsTab = .general

    /// Sparkle updater retrieved via AppDelegate.shared to avoid unreliable NSApp.delegate cast.
    private var updater: SPUUpdater? {
        AppDelegate.shared?.updaterController.updater
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            ModelsSettingsTab()
                .tabItem { Label("Models", systemImage: "globe") }
                .tag(SettingsTab.models)

            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsTab.shortcuts)

            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)

            PermissionsSettingsTab()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)

            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
                .tag(SettingsTab.backup)

            AboutSettingsTab(updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 550, height: 500)
        .onAppear { consumePendingTab() }
        .onChange(of: SettingsNavigator.shared.pendingTab) { _, _ in consumePendingTab() }
    }

    private func consumePendingTab() {
        guard let tab = SettingsNavigator.shared.pendingTab else { return }
        selectedTab = tab
        SettingsNavigator.shared.pendingTab = nil
    }
}
