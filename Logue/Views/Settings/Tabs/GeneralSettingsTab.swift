import ServiceManagement
import SwiftUI

/// Appearance mode preference for the app.
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// Combined settings tab: Startup, Theme, Editor, Shortcuts, Data.
struct GeneralSettingsTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("editorFontSize") private var editorFontSize: Double = 15
    @AppStorage(AppConstants.UserDefaultsKeys.autoSortCheckedItems) private var autoSortCheckedItems = false
    @AppStorage(AppConstants.UserDefaultsKeys.groupByDate) private var groupByDate = true
    @AppStorage(AppConstants.UserDefaultsKeys.hasClearedSeedData) private var hasClearedSeedData = false
    @AppStorage(AppConstants.UserDefaultsKeys.autoSaveSummaryToDocument) private var autoSaveSummaryToDocument = true
    @AppStorage(AppConstants.UserDefaultsKeys.sidebarSpaceSortOrder) private var sidebarSpaceSortOrderRaw = SidebarSpaceSortOrder.custom.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.webSearchEnabled) private var webSearchEnabled = false

    @State private var shortcutManager = ShortcutManager.shared

    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpaceStore.self) private var spaceStore

    @State private var showClearConfirmation = false
    @State private var showLoadConfirmation = false
    @State private var showWelcomeTour = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                Button {
                    showWelcomeTour = true
                } label: {
                    Label("Show welcome tour", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
            }

            Section("Theme") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) {
                    applyAppearance()
                }
            }

            Section("Sidebar") {
                Picker("Sort Spaces By", selection: Binding(
                    get: { SidebarSpaceSortOrder(rawValue: sidebarSpaceSortOrderRaw) ?? .custom },
                    set: { sidebarSpaceSortOrderRaw = $0.rawValue }
                )) {
                    ForEach(SidebarSpaceSortOrder.allCases, id: \.self) { order in
                        Text(order.label).tag(order)
                    }
                }
                .onChange(of: sidebarSpaceSortOrderRaw) {
                    spaceStore.sortRevision += 1
                }
            }

            Section("Editor") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(editorFontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $editorFontSize, in: 12 ... 24, step: 1) {
                    Text("Font Size")
                } minimumValueLabel: {
                    Text("12").font(.caption)
                } maximumValueLabel: {
                    Text("24").font(.caption)
                }

                Toggle(isOn: $autoSortCheckedItems) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically sort checked items")
                        Text("Move checklist items to the bottom as they are checked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $groupByDate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group notes by date")
                        Text("Group documents and meetings into sections like Today, Yesterday, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Meetings") {
                Toggle(isOn: $autoSaveSummaryToDocument) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-save summary to document")
                        Text("Automatically create a linked document from the meeting summary when recording ends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Shortcuts") {
                ShortcutRow(
                    title: "Ask Logue",
                    shortcut: $shortcutManager.commandCenterShortcut
                ) { newShortcut in
                    shortcutManager.updateCommandCenterShortcut(newShortcut)
                }
            }

            Section("Ask Logue") {
                Toggle(isOn: $webSearchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Web Search")
                        Text(
                            "Lets the agent search and fetch public web pages via DuckDuckGo. "
                                + "Off by default — Logue stays fully local until you enable this."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Data") {
                if hasClearedSeedData {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Example Data")
                            Text("Load sample documents, meetings, and spaces.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load Examples") {
                            showLoadConfirmation = true
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Example Data")
                            Text("Remove all sample documents, meetings, and spaces.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Examples", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showWelcomeTour) {
            OnboardingV2View()
        }
        .onAppear { applyAppearance() }
        .confirmationDialog(
            "Clear all example data?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Examples", role: .destructive) {
                documentStore.clearAllData()
                meetingStore.clearAllData()
                spaceStore.clearAllData()
                hasClearedSeedData = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all sample documents, meetings, and spaces. This cannot be undone.")
        }
        .confirmationDialog(
            "Load example data?",
            isPresented: $showLoadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Load Examples") {
                loadSeedData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will add sample documents, meetings, and spaces to your library.")
        }
    }

    private func loadSeedData() {
        documentStore.documents = DocumentStore.makeSeedDocuments()
        documentStore.rebuildIndexMap()
        documentStore.loadedSeedData = true
        documentStore.saveToDisk()
        meetingStore.meetings = MeetingStore.makeSeedMeetings()
        meetingStore.rebuildIndexMap()
        meetingStore.loadedSeedData = true
        meetingStore.saveToDisk()
        spaceStore.spaces = SpaceStore.makeSeedSpaces()
        spaceStore.loadedSeedData = true
        spaceStore.saveToDisk()
        hasClearedSeedData = false
    }

    private func applyAppearance() {
        let appearance: NSAppearance? = switch appearanceMode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
    }
}
