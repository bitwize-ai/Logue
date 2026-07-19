import Foundation
import os.log

/// Central observable space store. Persists to Application Support as JSON.
@Observable
@MainActor
final class SpaceStore {
    static let shared = SpaceStore()
    private init() {
        Task { await loadFromDiskAsync() }
    }

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "SpaceStore")

    // MARK: - State

    var spaces: [Space] = []

    /// True once `loadFromDiskAsync()` has finished.
    private(set) var isLoaded = false
    /// True only when seed/sample data was actually loaded (not real user data from disk).
    var loadedSeedData = false

    /// Serialized save task — cancels previous in-flight write so the latest snapshot always wins.
    @ObservationIgnored private var _saveTask: Task<Void, Never>?

    /// Bumped when the sidebar sort preference changes to trigger recomputation of sorted properties.
    var sortRevision: Int = 0

    // MARK: - Tree Queries

    private var currentSortOrder: SidebarSpaceSortOrder {
        let raw = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.sidebarSpaceSortOrder) ?? ""
        return SidebarSpaceSortOrder(rawValue: raw) ?? .custom
    }

    private func sortedSpaces(_ list: [Space]) -> [Space] {
        _ = sortRevision
        switch currentSortOrder {
        case .custom:
            return list.sorted { $0.sortOrder < $1.sortOrder }
        case .nameAZ:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameZA:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .createdNewest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest:
            return list.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Top-level spaces (no parent).
    var topLevelSpaces: [Space] {
        sortedSpaces(spaces.filter { $0.parentID == nil })
    }

    /// Direct children of a given space.
    func children(of spaceID: UUID) -> [Space] {
        sortedSpaces(spaces.filter { $0.parentID == spaceID })
    }

    /// Breadcrumb path from root to the given space (inclusive).
    func path(to spaceID: UUID) -> [Space] {
        var result: [Space] = []
        var current = space(for: spaceID)
        while let node = current {
            result.insert(node, at: 0)
            current = node.parentID.flatMap { space(for: $0) }
        }
        return result
    }

    /// All descendant space IDs (recursive). Includes visited-node protection against circular references.
    func allDescendantIDs(of spaceID: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var queue = children(of: spaceID).map(\.id)
        while !queue.isEmpty {
            let id = queue.removeFirst()
            // Skip already-visited nodes to prevent infinite loops from circular parent-child data
            guard result.insert(id).inserted else { continue }
            queue.append(contentsOf: children(of: id).map(\.id))
        }
        return result
    }

    // MARK: - CRUD

    @discardableResult
    func createSpace(name: String, parentID: UUID? = nil) -> Space? {
        let siblings = spaces.filter { $0.parentID == parentID }
        let deduped = uniqueTitle(name, among: siblings.map(\.name))
        let maxOrder = siblings.map(\.sortOrder).max() ?? -1
        let space = Space(name: deduped, parentID: parentID, sortOrder: maxOrder + 1)
        spaces.append(space)
        saveToDisk()
        return space
    }

    func renameSpace(id: UUID, newName: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parentID = spaces[index].parentID
        let otherNames = spaces.filter { $0.id != id && $0.parentID == parentID }.map(\.name)
        spaces[index].name = uniqueTitle(trimmed, among: otherNames)
        saveToDisk()
    }

    func setSpaceIcon(id: UUID, icon: String?) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].icon = icon
        saveToDisk()
    }

    func setAIInsight(id: UUID, key: String, content: String, contentSignature: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        if spaces[index].aiInsights == nil {
            spaces[index].aiInsights = [:]
        }
        spaces[index].aiInsights?[key] = SpaceAIInsight(
            content: content,
            generatedAt: .now,
            contentSignature: contentSignature
        )
        saveToDisk()
    }

    /// Computes a lightweight content signature for staleness detection.
    /// Format: "docCount:meetingCount:wordBucket:analyzedMeetingCount"
    /// Word count is bucketed to nearest 200 so small edits don't trigger invalidation.
    static func contentSignature(
        spaceID: UUID,
        spaceStore: SpaceStore,
        documentStore: DocumentStore,
        meetingStore: MeetingStore
    ) -> String {
        let allIDs = spaceStore.allDescendantIDs(of: spaceID).union([spaceID])
        let docs = documentStore.activeDocuments.filter { doc in
            doc.spaceID.map { allIDs.contains($0) } ?? false
        }
        let meetings = meetingStore.activeMeetings.filter { meeting in
            meeting.spaceID.map { allIDs.contains($0) } ?? false
        }
        let wordCount = docs.reduce(0) { $0 + $1.body.split(separator: " ").count }
        let wordBucket = (wordCount / 200) * 200
        let analyzedCount = meetings.filter { $0.summary != nil || $0.smartMinutes != nil }.count
        return "\(docs.count):\(meetings.count):\(wordBucket):\(analyzedCount)"
    }

    func toggleExpanded(id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].isExpanded.toggle()
        saveToDisk()
    }

    /// Expands all ancestor spaces along the path to the given space,
    /// so the sidebar tree reveals it when navigating from the content pane.
    func expandPath(to spaceID: UUID) {
        let ancestors = path(to: spaceID)
        var changed = false
        for ancestor in ancestors {
            if let index = spaces.firstIndex(where: { $0.id == ancestor.id }), !spaces[index].isExpanded {
                spaces[index].isExpanded = true
                changed = true
            }
        }
        if changed {
            saveToDisk()
        }
    }

    func deleteSpace(id: UUID) {
        // Recursively delete child spaces
        let childIDs = allDescendantIDs(of: id)
        let allIDs = childIDs.union([id])

        // Trash all documents and meetings in this space and descendants
        for spaceID in allIDs {
            DocumentStore.shared.trashDocuments(inSpace: spaceID)
            MeetingStore.shared.trashMeetings(inSpace: spaceID)
        }
        spaces.removeAll { allIDs.contains($0.id) }
        saveToDisk()
    }

    func space(for id: UUID) -> Space? {
        spaces.first { $0.id == id }
    }

    func moveSpace(id: UUID, toParent newParentID: UUID?) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        // Prevent moving a space into its own descendant
        if let newParentID, allDescendantIDs(of: id).contains(newParentID) {
            return
        }
        spaces[index].parentID = newParentID
        let siblings = spaces.filter { $0.parentID == newParentID && $0.id != id }
        spaces[index].sortOrder = (siblings.map(\.sortOrder).min() ?? 1) - 1
        saveToDisk()
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return support.appendingPathComponent("Logue/spaces.json")
    }

    // Sec-2: Use Task.detached to avoid blocking @MainActor
    func saveToDisk() {
        _saveTask?.cancel()
        let snapshot = spaces
        let url = storageURL
        _saveTask = Task.detached(priority: .utility) {
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                guard !Task.isCancelled else { return }
                let data = try EncryptionManager.encryptCodable(snapshot)
                guard !Task.isCancelled else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                guard !Task.isCancelled else { return }
                Logger(subsystem: AppConstants.bundleID, category: "SpaceStore")
                    .error("Failed to save spaces: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearAllData() {
        spaces = []
        saveToDisk()
    }

    private func loadFromDiskAsync() async {
        let url = storageURL
        let hasClearedSeed = UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.hasClearedSeedData)

        guard FileManager.default.fileExists(atPath: url.path) else {
            let useSeed = !hasClearedSeed
            spaces = useSeed ? Self.makeSeedSpaces() : []
            loadedSeedData = useSeed
            saveToDisk()
            isLoaded = true
            return
        }

        do {
            let loaded: [Space] = try await Task.detached {
                let data = try Data(contentsOf: url)
                return try EncryptionManager.decryptCodableWithFallback([Space].self, from: data)
            }.value

            guard !loaded.isEmpty else {
                let useSeed = !hasClearedSeed
                spaces = useSeed ? Self.makeSeedSpaces() : []
                loadedSeedData = useSeed
                saveToDisk()
                isLoaded = true
                return
            }
            spaces = loaded
            isLoaded = true
        } catch {
            logger.error("Failed to load spaces from disk: \(error.localizedDescription, privacy: .public)")
            let useSeed = !hasClearedSeed
            spaces = useSeed ? Self.makeSeedSpaces() : []
            loadedSeedData = useSeed
            saveToDisk()
            isLoaded = true
        }
    }
}
