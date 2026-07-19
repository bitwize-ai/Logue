import SwiftUI

/// Settings tab for exporting, importing, and iCloud backup of app data.
struct BackupSettingsTab: View {
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(DocumentStore.self) private var documentStore
    @Environment(SpaceStore.self) private var spaceStore

    @State private var backupManager = BackupManager.shared
    @State private var importMode: BackupManager.ImportMode = .merge
    @State private var showImportConfirmation = false
    @State private var showReplaceWarning = false
    @State private var showICloudRestoreConfirmation = false
    @State private var showICloudReplaceWarning = false
    @State private var selectedICloudEntry: BackupManager.ICloudBackupEntry?

    var body: some View {
        Form {
            iCloudSection
            localExportSection
            localImportSection

            // MARK: - Status

            if let message = backupManager.statusMessage {
                Section {
                    Label(
                        message,
                        systemImage: message.contains("failed") ? "exclamationmark.triangle" : "checkmark.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(message.contains("failed") ? .red : AppThemeConstants.success)
                }
            }

            // MARK: - Privacy

            Section {
                PrivacyBadge(
                    "Local backups stay on your Mac. iCloud backups are encrypted end-to-end by Apple.",
                    style: .standard
                )
            } header: {
                Text("Privacy & Security")
            }
        }
        .formStyle(.grouped)
        .onAppear { backupManager.refreshICloudBackups() }
        .confirmationDialog("Import backup?", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("Import & Merge") { performLocalImport(mode: .merge) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New items from the backup will be added. Existing items will not be changed.")
        }
        .confirmationDialog("Replace all data?", isPresented: $showReplaceWarning, titleVisibility: .visible) {
            Button("Replace All Data", role: .destructive) { performLocalImport(mode: .replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all current data and replace it with the backup. This cannot be undone.")
        }
        .confirmationDialog(
            "Restore from iCloud?",
            isPresented: $showICloudRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Merge with existing data") { restoreSelectedICloudBackup(mode: .merge) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let entry = selectedICloudEntry {
                Text("This will merge data from \(entry.id) into your current data.")
            }
        }
        .confirmationDialog(
            "Replace all data from iCloud?",
            isPresented: $showICloudReplaceWarning,
            titleVisibility: .visible
        ) {
            Button("Replace All Data", role: .destructive) { restoreSelectedICloudBackup(mode: .replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all current data and replace it with the iCloud backup. This cannot be undone.")
        }
    }

    // MARK: - iCloud Section

    private var iCloudSection: some View {
        Section {
            if backupManager.isICloudAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("iCloud Drive", systemImage: "icloud.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(AppThemeConstants.accent)

                        Spacer()

                        Button {
                            backupManager.backupToiCloud(
                                meetingStore: meetingStore,
                                documentStore: documentStore,
                                spaceStore: spaceStore
                            )
                        } label: {
                            if backupManager.isSyncingToiCloud {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppThemeConstants.accent)
                        .controlSize(.small)
                        .disabled(backupManager.isSyncingToiCloud)
                        .accessibilityLabel("Back up to iCloud")
                        .accessibilityHint("Saves an encrypted backup to your iCloud Drive")
                    }

                    Text("Backups are encrypted before uploading. They persist even if you uninstall Logue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastSync = backupManager.lastICloudBackupDate {
                        Text("Last iCloud backup: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // iCloud backup list
                    if !backupManager.iCloudBackups.isEmpty {
                        Divider()

                        Text("Available iCloud Backups")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(backupManager.iCloudBackups) { entry in
                            iCloudBackupRow(entry)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Not Available")
                            .font(.callout.weight(.medium))
                        Text("Sign in to iCloud in System Settings to enable cloud backups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("iCloud Backup")
        }
    }

    private func iCloudBackupRow(_ entry: BackupManager.ICloudBackupEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Button {
                    selectedICloudEntry = entry
                    showICloudRestoreConfirmation = true
                } label: {
                    Label("Restore (Merge)", systemImage: "arrow.down.circle")
                }

                Button {
                    selectedICloudEntry = entry
                    showICloudReplaceWarning = true
                } label: {
                    Label("Restore (Replace All)", systemImage: "arrow.counterclockwise.circle")
                }

                Divider()

                Button(role: .destructive) {
                    backupManager.deleteICloudBackup(entry)
                } label: {
                    Label("Delete Backup", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel("Backup options for \(entry.date.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    // MARK: - Local Export Section

    private var localExportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Export to a file on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    dataSummary

                    Spacer()

                    Button {
                        backupManager.exportBackup(
                            meetingStore: meetingStore,
                            documentStore: documentStore,
                            spaceStore: spaceStore
                        )
                    } label: {
                        Label("Export to File", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(backupManager.isExporting)
                    .accessibilityLabel("Export backup to file")
                    .accessibilityHint("Saves all data to a local file")
                }

                if let lastExport = backupManager.lastExportDate {
                    Text("Last local export: \(lastExport.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Local Export")
        }
    }

    // MARK: - Local Import Section

    private var localImportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Restore from a local backup file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Import mode", selection: $importMode) {
                    Text("Merge — add new items, keep existing").tag(BackupManager.ImportMode.merge)
                    Text("Replace — overwrite all current data").tag(BackupManager.ImportMode.replace)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Import mode")

                HStack {
                    Spacer()

                    Button {
                        if importMode == .replace {
                            showReplaceWarning = true
                        } else {
                            showImportConfirmation = true
                        }
                    } label: {
                        Label("Import from File", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(backupManager.isImporting)
                    .accessibilityLabel("Import backup from file")
                    .accessibilityHint("Restores data from a local backup file")
                }
            }
        } header: {
            Text("Local Import")
        }
    }

    // MARK: - Helpers

    private var dataSummary: some View {
        HStack(spacing: 16) {
            summaryItem(count: meetingStore.meetings.count, label: "Meetings", icon: "mic.fill")
            summaryItem(count: documentStore.documents.count, label: "Documents", icon: "doc.text.fill")
            summaryItem(count: spaceStore.spaces.count, label: "Spaces", icon: "folder.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func summaryItem(count: Int, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count) \(label)")
        }
        .accessibilityElement(children: .combine)
    }

    private func performLocalImport(mode: BackupManager.ImportMode) {
        backupManager.importBackup(
            meetingStore: meetingStore,
            documentStore: documentStore,
            spaceStore: spaceStore,
            mode: mode
        )
    }

    private func restoreSelectedICloudBackup(mode: BackupManager.ImportMode) {
        guard let entry = selectedICloudEntry else { return }
        backupManager.restoreFromiCloud(
            entry: entry,
            meetingStore: meetingStore,
            documentStore: documentStore,
            spaceStore: spaceStore,
            mode: mode
        )
    }
}
