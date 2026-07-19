import AppKit
import Foundation
import os.log
import UniformTypeIdentifiers

/// Handles full-app backup export and import (meetings, documents, folders).
///
/// Export produces a single `.loguebackup` JSON file containing all user data.
/// Import reads such a file and merges or replaces the current data.
@MainActor
@Observable
final class BackupManager {
    static let shared = BackupManager()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "BackupManager")

    private static let iCloudContainerID = "iCloud.com.bitwize.logue"
    private static let iCloudBackupFolder = "Backups"

    // MARK: - State

    var isExporting = false
    var isImporting = false
    var isSyncingToiCloud = false
    var lastExportDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackupExportDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackupExportDate") }
    }

    var lastICloudBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastICloudBackupDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastICloudBackupDate") }
    }

    /// Whether iCloud Drive is available on this Mac.
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var iCloudBackups: [ICloudBackupEntry] = []

    var statusMessage: String?

    struct ICloudBackupEntry: Identifiable {
        let id: String // filename
        let url: URL
        let date: Date
        let size: Int64
    }

    // MARK: - Backup Envelope

    struct BackupEnvelope: Codable {
        let version: Int
        let exportedAt: Date
        let appVersion: String
        let meetings: [MeetingNote]
        let documents: [WritingDocument]
        let spaces: [Space]

        static let currentVersion = 1
    }

    // MARK: - Export

    /// Exports all user data to a `.loguebackup` file via NSSavePanel.
    func exportBackup(
        meetingStore: MeetingStore,
        documentStore: DocumentStore,
        spaceStore: SpaceStore
    ) {
        isExporting = true
        statusMessage = nil

        let envelope = BackupEnvelope(
            version: BackupEnvelope.currentVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            meetings: meetingStore.meetings,
            documents: documentStore.documents,
            spaces: spaceStore.spaces
        )

        do {
            let data = try EncryptionManager.encryptCodable(envelope)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "loguebackup") ?? .json]
            panel.nameFieldStringValue = backupFilename()
            panel.canCreateDirectories = true
            panel.title = "Export Logue Backup"
            panel.message = "Choose where to save your backup file."

            panel.begin { @MainActor [weak self] response in
                guard let self else { return }
                defer { self.isExporting = false }
                guard response == .OK, let url = panel.url else {
                    statusMessage = nil
                    return
                }
                do {
                    try data.write(to: url, options: .atomic)
                    // Restrict file permissions to owner-only (0600) for exported backup
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o600], ofItemAtPath: url.path
                    )
                    lastExportDate = Date()
                    statusMessage = "Backup exported successfully."
                    logger.info("Backup exported: \(url.lastPathComponent) (\(data.count) bytes)")
                } catch {
                    statusMessage = "Export failed: \(error.localizedDescription)"
                    logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            isExporting = false
            statusMessage = "Export failed: \(error.localizedDescription)"
            logger.error("Export encoding failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Import

    enum ImportMode {
        /// Merge imported data with existing — skip duplicates by ID.
        case merge
        /// Replace all existing data with imported data.
        case replace
    }

    /// Imports a `.loguebackup` file via NSOpenPanel.
    func importBackup(
        meetingStore: MeetingStore,
        documentStore: DocumentStore,
        spaceStore: SpaceStore,
        mode: ImportMode
    ) {
        isImporting = true
        statusMessage = nil

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "loguebackup") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Logue Backup"
        panel.message = "Select a .loguebackup or .json file to restore."

        panel.begin { @MainActor [weak self] response in
            guard let self else { return }
            defer { self.isImporting = false }
            guard response == .OK, let url = panel.url else {
                statusMessage = nil
                return
            }
            do {
                let data = try Data(contentsOf: url)
                let envelope = try EncryptionManager.decryptCodableWithFallback(BackupEnvelope.self, from: data)

                applyImport(
                    envelope: envelope,
                    meetingStore: meetingStore,
                    documentStore: documentStore,
                    spaceStore: spaceStore,
                    mode: mode
                )
                let mc = envelope.meetings.count
                let dc = envelope.documents.count
                let sc = envelope.spaces.count
                logger.info("Backup imported: \(mc) meetings, \(dc) documents, \(sc) spaces")
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
                logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyImport(
        envelope: BackupEnvelope,
        meetingStore: MeetingStore,
        documentStore: DocumentStore,
        spaceStore: SpaceStore,
        mode: ImportMode
    ) {
        // Sec-3: Validate backup version before importing
        guard envelope.version <= BackupEnvelope.currentVersion else {
            statusMessage = "This backup was created by a newer version of Logue. Please update the app."
            return
        }

        switch mode {
        case .replace:
            meetingStore.meetings = envelope.meetings
            documentStore.documents = envelope.documents
            spaceStore.spaces = envelope.spaces
            // B-N7: Rebuild index maps and invalidate caches after replace-import
            meetingStore.rebuildIndexMap()
            meetingStore.invalidateCaches()
            documentStore.rebuildIndexMap()
            documentStore.invalidateCaches()
            statusMessage = "Restored \(envelope.meetings.count) meetings, \(envelope.documents.count) documents, \(envelope.spaces.count) spaces."

        case .merge:
            let existingMeetingIDs = Set(meetingStore.meetings.map(\.id))
            let newMeetings = envelope.meetings.filter { !existingMeetingIDs.contains($0.id) }
            meetingStore.meetings.append(contentsOf: newMeetings)

            let existingDocIDs = Set(documentStore.documents.map(\.id))
            let newDocs = envelope.documents.filter { !existingDocIDs.contains($0.id) }
            documentStore.documents.append(contentsOf: newDocs)

            let existingSpaceIDs = Set(spaceStore.spaces.map(\.id))
            let newSpaces = envelope.spaces.filter { !existingSpaceIDs.contains($0.id) }
            spaceStore.spaces.append(contentsOf: newSpaces)

            statusMessage = "Merged \(newMeetings.count) meetings, \(newDocs.count) documents, \(newSpaces.count) spaces."
            // B-N7: Rebuild index maps after merge-import too
            meetingStore.rebuildIndexMap()
            meetingStore.invalidateCaches()
            documentStore.rebuildIndexMap()
            documentStore.invalidateCaches()
        }

        meetingStore.saveToDisk()
        documentStore.saveToDisk()
        spaceStore.saveToDisk()
        MeetingMemoryIndex.shared.rebuildIndex(from: meetingStore.meetings)
    }

    // MARK: - iCloud Backup

    /// Saves an encrypted backup to the app's iCloud Drive container.
    func backupToiCloud(
        meetingStore: MeetingStore,
        documentStore: DocumentStore,
        spaceStore: SpaceStore
    ) {
        guard isICloudAvailable else {
            statusMessage = "iCloud is not available. Sign in to iCloud in System Settings."
            return
        }

        isSyncingToiCloud = true
        statusMessage = nil

        // Capture snapshots on MainActor before detaching to background
        let envelope = BackupEnvelope(
            version: BackupEnvelope.currentVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            meetings: meetingStore.meetings,
            documents: documentStore.documents,
            spaces: spaceStore.spaces
        )
        let filename = backupFilename()

        Task.detached { [weak self] in
            do {
                guard let self else { return }
                // Encrypt the backup before writing to iCloud
                let encryptedData = try EncryptionManager.encryptCodable(envelope)

                let backupDir = try iCloudBackupDirectory()
                let fileURL = backupDir.appendingPathComponent(filename)
                try encryptedData.write(to: fileURL, options: .atomic)

                // Prune old backups — keep last 5
                try pruneOldICloudBackups(in: backupDir, keep: 5)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    lastICloudBackupDate = Date()
                    statusMessage = "Backed up to iCloud Drive (encrypted)."
                    isSyncingToiCloud = false
                    logger.info("iCloud backup saved: \(filename)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    statusMessage = "iCloud backup failed: \(error.localizedDescription)"
                    isSyncingToiCloud = false
                    logger.error("iCloud backup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Lists available backups in iCloud Drive.
    func refreshICloudBackups() {
        guard isICloudAvailable else {
            iCloudBackups = []
            return
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let backupDir = try iCloudBackupDirectory()
                let contents = try FileManager.default.contentsOfDirectory(
                    at: backupDir,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                let entries: [ICloudBackupEntry] = contents
                    .filter { $0.pathExtension == "loguebackup" }
                    .compactMap { url in
                        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        let date = values?.contentModificationDate ?? Date.distantPast
                        let size = Int64(values?.fileSize ?? 0)
                        return ICloudBackupEntry(id: url.lastPathComponent, url: url, date: date, size: size)
                    }
                    .sorted { $0.date > $1.date }

                await MainActor.run {
                    self.iCloudBackups = entries
                }
            } catch {
                await MainActor.run {
                    self.iCloudBackups = []
                    self.logger.warning("Could not list iCloud backups: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Restores from a specific iCloud backup.
    func restoreFromiCloud(
        entry: ICloudBackupEntry,
        meetingStore: MeetingStore,
        documentStore: DocumentStore,
        spaceStore: SpaceStore,
        mode: ImportMode
    ) {
        isImporting = true
        statusMessage = nil

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: entry.url)
                // Backups are encrypted — decrypt first, fall back to plain JSON for legacy
                let envelope = try EncryptionManager.decryptCodableWithFallback(BackupEnvelope.self, from: data)

                await MainActor.run {
                    self.applyImport(
                        envelope: envelope,
                        meetingStore: meetingStore,
                        documentStore: documentStore,
                        spaceStore: spaceStore,
                        mode: mode
                    )
                    self.isImporting = false
                    self.logger.info("Restored from iCloud: \(entry.id)")
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "iCloud restore failed: \(error.localizedDescription)"
                    self.isImporting = false
                    self.logger.error("iCloud restore failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Deletes a specific iCloud backup.
    func deleteICloudBackup(_ entry: ICloudBackupEntry) {
        do {
            try FileManager.default.removeItem(at: entry.url)
            iCloudBackups.removeAll { $0.id == entry.id }
            statusMessage = "Deleted backup: \(entry.id)"
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - iCloud Helpers

    nonisolated private func iCloudBackupDirectory() throws -> URL {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: Self.iCloudContainerID
        )
        else {
            throw BackupError.iCloudUnavailable
        }
        let backupDir = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.iCloudBackupFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        return backupDir
    }

    nonisolated private func pruneOldICloudBackups(in directory: URL, keep: Int) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backups = contents
            .filter { $0.pathExtension == "loguebackup" }
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lDate > rDate
            }
        if backups.count > keep {
            for old in backups.dropFirst(keep) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    enum BackupError: LocalizedError {
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: "iCloud Drive is not available. Please sign in to iCloud in System Settings."
            }
        }
    }

    // MARK: - Helpers

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private func backupFilename() -> String {
        "Logue-Backup-\(Self.filenameFormatter.string(from: Date())).loguebackup"
    }
}
