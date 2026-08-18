import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar with unified space tree for the 2-column Notion-style layout.
/// Shows Overview, Spaces (recursive tree with mixed content), All Documents, All Meetings, Trash, and Settings.
struct CategorySidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(SpaceStore.self) private var spaceStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    /// `@State` rather than `@ObservedObject`: `DocumentStorage` is `@Observable`.
    @State private var documentStorage = DocumentStorage.shared
    @State private var taskStore = TaskStore.shared

    @State private var isAddingSpace = false
    @State private var newSpaceName = ""
    @State private var renamingSpaceID: UUID?
    @State private var renameSpaceText = ""
    @State private var iconPickerSpaceID: UUID?
    @FocusState private var isNewSpaceFieldFocused: Bool
    @State private var showAllSpaces = false

    private let newSpaceFieldID = "newSpaceField"
    private static let maxCollapsedSpaces = 8

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    // Overview
                    // Accessibility note (macOS 26): do NOT add `.accessibilityAddTraits(.isButton)`
                    // to List selection rows — it replaces the AXStaticText element with a synthetic
                    // AXButton whose title is empty, breaking VoiceOver. Rely on the selection-row
                    // role + AXValue text (which lands from the Label's visible content) instead.
                    Section {
                        Label("Home", systemImage: "house")
                            .tag(SidebarItem.home)
                            .accessibilityLabel("Home")
                            .accessibilityHint("Ask Logue, and see what needs you today")
                    }

                    // Pinned & Recent
                    Section {
                        Label {
                            HStack {
                                Text("Pinned")
                                Spacer()
                                let pinCount = documentStore.pinnedDocuments.count
                                    + meetingStore.activeMeetings.filter(\.isPinned).count
                                if pinCount > 0 {
                                    Text("\(pinCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } icon: {
                            Image(systemName: "pin")
                        }
                        .tag(SidebarItem.pinned)
                        .accessibilityLabel(pinnedAccessibilityLabel)

                        Label("Recent", systemImage: "clock")
                            .tag(SidebarItem.recent)
                            .accessibilityLabel("Recent")
                    }

                    // Smart Views
                    Section("Library") {
                        Label {
                            HStack {
                                Text("All Documents")
                                Spacer()
                                Text("\(documentStore.activeDocuments.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                        .tag(SidebarItem.allDocuments)
                        .accessibilityLabel("All Documents, \(documentStore.activeDocuments.count) items")

                        Label {
                            HStack {
                                Text("All Meetings")
                                Spacer()
                                Text("\(meetingStore.activeMeetings.filter { !$0.isArchived }.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "waveform")
                        }
                        .tag(SidebarItem.allMeetings)
                        .accessibilityLabel("All Meetings, \(meetingStore.activeMeetings.filter { !$0.isArchived }.count) items")

                        Label {
                            HStack {
                                Text("Tasks")
                                Spacer()
                                let openCount = taskStore.openTasks.count
                                if openCount > 0 {
                                    Text("\(openCount)")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            hasOverdueTasks
                                                ? AnyShapeStyle(AppThemeConstants.error)
                                                : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                                        )
                                }
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                        .tag(SidebarItem.tasks)
                        .accessibilityLabel("Tasks, \(taskStore.openTasks.count) open")
                        .accessibilityHint("View and capture your own tasks")
                    }

                    // Phase H: AI Detector moved into the document Verify
                    // panel. Diagrammer + Slide Studio are now agent tools
                    // (`render_diagram`, `generate_slides`). The whole
                    // Productivity section is gone — chat is the entry
                    // point for those capabilities.

                    // Spaces (limited to first N when collapsed)
                    Section("Spaces") {
                        ForEach(visibleSpaces) { space in
                            SpaceTreeRow(
                                space: space, selection: $selection,
                                renamingSpaceID: $renamingSpaceID,
                                renameSpaceText: $renameSpaceText,
                                iconPickerSpaceID: $iconPickerSpaceID
                            )
                        }

                        if shouldCollapseSpaces {
                            Button {
                                withAnimation { showAllSpaces = true }
                            } label: {
                                Label(
                                    "Show \(spaceStore.topLevelSpaces.count - Self.maxCollapsedSpaces) more…",
                                    systemImage: "chevron.down"
                                )
                                .font(.callout).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if isAddingSpace {
                            newSpaceField { isAddingSpace = false }.id(newSpaceFieldID)
                        }

                        Button {
                            newSpaceName = ""
                            isAddingSpace = true
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                withAnimation { proxy.scrollTo(newSpaceFieldID, anchor: .bottom) }
                                isNewSpaceFieldFocused = true
                            }
                        } label: {
                            Label("New Space", systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Space")
                        .accessibilityHint("Creates a new space for organizing items")
                    }
                }
                .listStyle(.sidebar)
                .tint(AppThemeConstants.accent)
                .background(AppThemeConstants.chromeBackground)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        rescanButton
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newSpaceName = ""
                            isAddingSpace = true
                            Task {
                                try? await Task.sleep(for: AppConstants.Delays.focusActivation)
                                withAnimation { proxy.scrollTo(newSpaceFieldID, anchor: .bottom) }
                                isNewSpaceFieldFocused = true
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .help("New Space")
                        .accessibilityLabel("New Space")
                    }
                }
            } // ScrollViewReader

            Divider()

            // Pinned bottom — Trash & Settings always visible
            pinnedBottomBar
        }
    }

    // MARK: - Rescan

    /// Re-reads `~/Logue` on request.
    ///
    /// Icon only, and shown only when plain markdown storage is on — with the setting off there is no
    /// folder to read, so a button would be a promise the app cannot keep.
    ///
    /// Changes are picked up on their own three ways: the folder watcher, a scan at launch, and a
    /// quiet scan whenever the app becomes active. This is the fallback for what none of those cover
    /// — a watcher that could not start because the folder was on an unmounted drive, or a sync
    /// client that moves files without producing events the watcher sees. Rarely needed, and the only
    /// way to ask without quitting.
    @ViewBuilder
    private var rescanButton: some View {
        if documentStorage.mode.isMarkdown {
            Button {
                Task { await documentStorage.rescan() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    // A full turn per repeat, so the arrows land where they started and the
                    // spin reads as continuous rather than as a rock back and forth.
                    .rotationEffect(.degrees(documentStorage.isScanning ? 360 : 0))
                    .animation(rescanSpin, value: documentStorage.isScanning)
            }
            .disabled(documentStorage.isScanning)
            .help(rescanTooltip)
            .accessibilityLabel("Rescan Documents Folder")
        }
    }

    /// Spins while scanning; eases back to rest when it stops.
    ///
    /// The animation is chosen by the same flag that drives the angle, so stopping does not
    /// inherit `repeatForever` and leave the icon turning after the scan is over.
    private var rescanSpin: Animation {
        documentStorage.isScanning
            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
            : .easeOut(duration: 0.2)
    }

    private var rescanTooltip: String {
        guard let summary = documentStorage.lastScanSummary else {
            return "Check the Logue folder for changes made outside Logue"
        }
        return "Check the Logue folder for changes made outside Logue — last check: \(summary.lowercased())"
    }

    // MARK: - Task Counts

    /// Whether any open task is past its due date, so the count reads as urgent.
    private var hasOverdueTasks: Bool {
        taskStore.openTasks.contains { $0.isOverdue }
    }

    private var pinnedAccessibilityLabel: String {
        let count = documentStore.pinnedDocuments.count + meetingStore.activeMeetings.filter(\.isPinned).count
        return count > 0 ? "Pinned, \(count) items" : "Pinned"
    }

    // MARK: - Spaces Helpers

    private var shouldCollapseSpaces: Bool {
        spaceStore.topLevelSpaces.count > Self.maxCollapsedSpaces && !showAllSpaces
    }

    private var visibleSpaces: [Space] {
        shouldCollapseSpaces
            ? Array(spaceStore.topLevelSpaces.prefix(Self.maxCollapsedSpaces))
            : spaceStore.topLevelSpaces
    }

    // MARK: - Pinned Bottom Bar (Trash + Settings)

    private var pinnedBottomBar: some View {
        VStack(spacing: 0) {
            // Trash row — tappable, highlights when selected
            Button {
                selection = .trash
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .foregroundStyle(selection == .trash ? AppThemeConstants.accent : .secondary)
                        .frame(width: 20)
                    Text("Trash")
                    Spacer()
                    let trashCount = documentStore.trashedDocuments.count + meetingStore.trashedMeetings.count
                    if trashCount > 0 {
                        Text("\(trashCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    selection == .trash
                        ? AppThemeConstants.accent.opacity(AppThemeConstants.opacityLight)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trash")

            // Settings row
            Button {
                openSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Settings")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppThemeConstants.chromeBackground)
    }

    // MARK: - New Space Field

    private func newSpaceField(onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Space name", text: $newSpaceName, onCommit: {
                let trimmed = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let space = spaceStore.createSpace(name: trimmed) {
                        selection = .space(space.id)
                    }
                }
                isNewSpaceFieldFocused = false
                onDismiss()
            })
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($isNewSpaceFieldFocused)
            .onExitCommand {
                isNewSpaceFieldFocused = false
                onDismiss()
            }
        }
    }
}

// MARK: - SpaceTreeRow (Recursive View Struct — no AnyView)

// A concrete View struct for rendering a space in the sidebar tree.
// References itself recursively via ForEach for child spaces.
// This avoids AnyView type erasure, which breaks List selection highlights.
