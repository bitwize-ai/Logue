import Foundation
import os.log

/// Persistence methods extracted from MeetingStore.
/// Handles all file I/O: save, load, delete, bulk operations, and digest cache.
extension MeetingStore {
    // MARK: - Directory

    var meetingsDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/meetings")
    }

    // MARK: - Single Meeting Save

    /// Save a single meeting to its own file. Use this for single-meeting mutations.
    func saveMeeting(id: UUID) {
        guard let index = meetingIndex(for: id) else { return }
        let meeting = meetings[index]
        let url = meetingsDirectory.appendingPathComponent("\(id.uuidString).json")
        meetingSaveTasks[id]?.cancel()
        meetingSaveTasks[id] = Task.detached(priority: .utility) {
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard !Task.isCancelled else { return }
                let data = try EncryptionManager.encryptCodable(meeting)
                guard !Task.isCancelled else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                guard !Task.isCancelled else { return }
                Logger(subsystem: AppConstants.bundleID, category: "MeetingStore")
                    .error("Failed to save meeting \(id): \(error.localizedDescription, privacy: .public)")
            }
        }
        // Best-effort semantic re-index. Hash check inside `indexMeeting` skips work
        // when the transcript hasn't changed; trashed meetings are removed.
        Task.detached(priority: .utility) {
            await SemanticIndex.shared.indexMeeting(meeting)
        }
    }

    /// Delete the individual file for a meeting.
    func deleteMeetingFile(id: UUID) {
        let url = meetingsDirectory.appendingPathComponent("\(id.uuidString).json")
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Bulk Save

    /// Save all meetings (for bulk operations). Cancels previous in-flight write.
    /// Writes to a temp directory first, then replaces files — prevents partial state on crash.
    func saveToDisk() {
        bulkSaveTask?.cancel()
        let snapshot = meetings
        let dir = meetingsDirectory
        bulkSaveTask = Task.detached(priority: .utility) {
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory.appendingPathComponent("meetings-\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                guard !Task.isCancelled else {
                    try? fm.removeItem(at: tempDir)
                    return
                }
                // Write all files to temp directory first
                for meeting in snapshot {
                    guard !Task.isCancelled else {
                        try? fm.removeItem(at: tempDir)
                        return
                    }
                    let data = try EncryptionManager.encryptCodable(meeting)
                    let tempURL = tempDir.appendingPathComponent("\(meeting.id.uuidString).json")
                    try data.write(to: tempURL, options: .atomic)
                }
                // Move each temp file into the real directory (atomic per-file replace)
                guard !Task.isCancelled else {
                    try? fm.removeItem(at: tempDir)
                    return
                }
                for meeting in snapshot {
                    let src = tempDir.appendingPathComponent("\(meeting.id.uuidString).json")
                    let dst = dir.appendingPathComponent("\(meeting.id.uuidString).json")
                    _ = try? fm.replaceItemAt(dst, withItemAt: src)
                }
                try? fm.removeItem(at: tempDir)
            } catch {
                try? fm.removeItem(at: tempDir)
                guard !Task.isCancelled else { return }
                Logger(subsystem: AppConstants.bundleID, category: "MeetingStore")
                    .error("Failed to save meetings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Clear All

    func clearAllData() {
        meetings = []
        selectedMeetingID = nil
        cachedDigest = nil
        digestMeetingIDs = []
        invalidateCaches()
        let dir = meetingsDirectory
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: dir)
        }
        let cacheURL = digestCacheURL
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        MeetingMemoryIndex.shared.rebuildIndex(from: [])
        Task.detached(priority: .utility) {
            await SemanticIndex.shared.clearAll()
        }
    }

    // MARK: - Load from Disk

    func loadFromDiskAsync() async {
        let dir = meetingsDirectory
        let hasClearedSeed = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hasClearedSeedData)

        let dirExists = FileManager.default.fileExists(atPath: dir.path)
        guard dirExists else {
            let useSeed = !hasClearedSeed
            meetings = useSeed ? Self.makeSeedMeetings() : []
            loadedSeedData = useSeed
            rebuildIndexMap()
            selectedMeetingID = meetings.first?.id
            saveToDisk()
            isLoaded = true
            return
        }

        do {
            let loaded: [MeetingNote] = try await Task.detached {
                let fm = FileManager.default
                let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    .filter { $0.pathExtension == "json" }
                var result: [MeetingNote] = []
                for file in files {
                    do {
                        let data = try Data(contentsOf: file)
                        let meeting = try EncryptionManager.decryptCodableWithFallback(MeetingNote.self, from: data)
                        result.append(meeting)
                    } catch {
                        Logger(subsystem: AppConstants.bundleID, category: "MeetingStore")
                            .error("Failed to load meeting from \(file.lastPathComponent): \(error.localizedDescription, privacy: .public)")
                    }
                }
                return result.sorted { $0.createdAt > $1.createdAt }
            }.value

            guard !loaded.isEmpty else {
                meetings = []
                rebuildIndexMap()
                selectedMeetingID = nil
                isLoaded = true
                return
            }
            meetings = loaded
            rebuildIndexMap()
            MeetingMemoryIndex.shared.rebuildIndex(from: meetings)
            // Build semantic embedding index alongside the FTS5 keyword index.
            // Hash-checked inside `indexMeeting`, so this is cheap on repeat launches.
            let snapshot = meetings
            Task.detached(priority: .utility) {
                for meeting in snapshot {
                    await SemanticIndex.shared.indexMeeting(meeting)
                }
            }
            isLoaded = true
        } catch {
            logger.error("Failed to load meetings from disk: \(error.localizedDescription, privacy: .public)")
            let useSeed = !hasClearedSeed
            meetings = useSeed ? Self.makeSeedMeetings() : []
            loadedSeedData = useSeed
            rebuildIndexMap()
            selectedMeetingID = meetings.first?.id
            saveToDisk()
            isLoaded = true
        }
    }
}

// MARK: - Digest Cache Persistence

private struct DigestCache: Codable {
    let digest: DailyDigest
    let meetingIDs: Set<UUID>
    let date: Date
}

extension MeetingStore {
    var digestCacheURL: URL {
        meetingsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("daily_digest_cache.json")
    }

    func saveDigestCache() {
        guard let digest = cachedDigest else { return }
        let cache = DigestCache(
            digest: digest,
            meetingIDs: digestMeetingIDs,
            date: Date()
        )
        let url = digestCacheURL
        Task.detached(priority: .utility) {
            do {
                let data = try EncryptionManager.encryptCodable(cache)
                try data.write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "MeetingStore")
                    .error("Failed to save digest cache: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func loadDigestCache() {
        let url = digestCacheURL
        Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try Data(contentsOf: url)
                let cache = try EncryptionManager.decryptCodableWithFallback(DigestCache.self, from: data)
                guard Calendar.current.isDateInToday(cache.date) else {
                    await MainActor.run {
                        self?.cachedDigest = nil
                        self?.digestMeetingIDs = []
                    }
                    return
                }
                await MainActor.run {
                    self?.cachedDigest = cache.digest
                    self?.digestMeetingIDs = cache.meetingIDs
                }
            } catch {
                await MainActor.run {
                    self?.cachedDigest = nil
                    self?.digestMeetingIDs = []
                }
            }
        }
    }
}
