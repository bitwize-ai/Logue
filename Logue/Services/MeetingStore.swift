import Foundation
import os.log

/// Central observable meeting library. Persists to Application Support as JSON.
/// Follows the same pattern as DocumentStore.
@Observable
@MainActor
final class MeetingStore: MeetingRepository, MeetingSegmentManager, MeetingSpeakerManager,
    MeetingAIContentManager, MeetingMetadataManager, MeetingSearchable, MeetingSpaceOrganizer
{
    static let shared = MeetingStore()
    private init() {
        Task {
            await loadFromDiskAsync()
            loadDigestCache()
        }
    }

    let logger = Logger(subsystem: AppConstants.bundleID, category: "MeetingStore")

    // MARK: - State

    var meetings: [MeetingNote] = [] {
        didSet {
            let newSig = cacheSig(meetings)
            if newSig != _lastCacheSig {
                _lastCacheSig = newSig
                invalidateCaches()
            }
        }
    }

    /// Lightweight signature of the fields that affect cached subsets (pinned, archived, trashed, tags, count).
    @ObservationIgnored private var _lastCacheSig: Int = 0

    private func cacheSig(_ list: [MeetingNote]) -> Int {
        var hasher = Hasher()
        hasher.combine(list.count)
        for meeting in list {
            hasher.combine(meeting.id)
            hasher.combine(meeting.isPinned)
            hasher.combine(meeting.isArchived)
            hasher.combine(meeting.isTrashed)
            hasher.combine(meeting.tags)
        }
        return hasher.finalize()
    }

    var selectedMeetingID: UUID?

    /// Tracks which meetings currently have an AI summary generation in progress.
    /// Used to prevent duplicate concurrent generation from multiple UI entry points.
    /// Internal setter required for MeetingStore+AI.swift extension access
    var generatingMeetingIDs: Set<UUID> = []

    /// True once `loadFromDiskAsync()` has finished (prevents views from rendering stale empty state).
    var isLoaded = false
    /// True only when seed/sample data was actually loaded (not real user data from disk).
    var loadedSeedData = false
    /// Transient signal — when set, MeetingWorkspaceView auto-starts recording for this meeting.
    var pendingAutoRecord: UUID?

    /// Serialized save task — cancels previous in-flight write so the latest snapshot always wins.
    @ObservationIgnored var bulkSaveTask: Task<Void, Never>?
    @ObservationIgnored var meetingSaveTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Daily Digest Cache

    /// Cached digest persisted across tab switches / app restarts.
    var cachedDigest: DailyDigest?
    /// Meeting IDs the cached digest was generated from.
    var digestMeetingIDs: Set<UUID> = []

    /// Tracks which meetings have already had auto-title generation triggered.
    private var hasTriggeredAutoTitle: [UUID: Bool] = [:]
    /// Task for debounced auto-title generation during recording.
    private var titleGenerationTask: Task<Void, Never>?

    /// UUID → array index map for O(1) meeting lookups. Rebuilt on load and mutations.
    @ObservationIgnored private var _meetingIndexMap: [UUID: Int] = [:]

    /// O(1) lookup for meeting index by UUID, with fallback to linear search + map repair.
    func meetingIndex(for id: UUID) -> Int? {
        if let idx = _meetingIndexMap[id], idx < meetings.count, meetings[idx].id == id {
            return idx
        }
        // Map was stale — repair via linear search
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else {
            _meetingIndexMap.removeValue(forKey: id)
            return nil
        }
        _meetingIndexMap[id] = idx
        return idx
    }

    /// Rebuild the UUID→Index map after bulk changes (load, delete, reorder).
    func rebuildIndexMap() {
        _meetingIndexMap = Dictionary(uniqueKeysWithValues: meetings.enumerated().map { ($1.id, $0) })
    }

    var selectedMeeting: MeetingNote? {
        guard let id = selectedMeetingID else { return nil }
        guard let idx = meetingIndex(for: id) else { return nil }
        return meetings[idx]
    }

    // MARK: - Computed Subsets (cached)

    @ObservationIgnored private var _cachedRecent: [MeetingNote]?
    @ObservationIgnored private var _cachedPinned: [MeetingNote]?
    @ObservationIgnored private var _cachedArchived: [MeetingNote]?
    @ObservationIgnored var cachedAllTags: [String]?

    func invalidateCaches() {
        _cachedRecent = nil
        _cachedPinned = nil
        _cachedArchived = nil
        cachedAllTags = nil
    }

    var activeMeetings: [MeetingNote] {
        meetings.filter { !$0.isTrashed }
    }

    var recentMeetings: [MeetingNote] {
        if let cached = _cachedRecent {
            return cached
        }
        let result = activeMeetings
            .filter { !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map { $0 }
        _cachedRecent = result
        return result
    }

    var pinnedMeetings: [MeetingNote] {
        if let cached = _cachedPinned {
            return cached
        }
        let result = activeMeetings.filter(\.isPinned)
        _cachedPinned = result
        return result
    }

    var archivedMeetings: [MeetingNote] {
        if let cached = _cachedArchived {
            return cached
        }
        let result = activeMeetings.filter(\.isArchived)
        _cachedArchived = result
        return result
    }

    var trashedMeetings: [MeetingNote] {
        meetings.filter(\.isTrashed)
    }

    // MARK: - CRUD

    @discardableResult
    func createMeeting(
        title: String = "Untitled Meeting",
        mode: RecordingMode = .inPerson,
        template: MeetingTemplate = .general,
        inSpace spaceID: UUID? = nil
    ) -> MeetingNote {
        let deduped = uniqueTitle(title, among: activeMeetings.map(\.title))
        let meeting = MeetingNote(title: deduped, recordingMode: mode, template: template, spaceID: spaceID)
        meetings.insert(meeting, at: 0)
        rebuildIndexMap()
        selectedMeetingID = meeting.id
        invalidateCaches()
        saveMeeting(id: meeting.id)
        return meeting
    }

    @discardableResult
    func createVoiceNote(inSpace spaceID: UUID? = nil) -> MeetingNote {
        let baseTitle = "Voice Note \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        let deduped = uniqueTitle(baseTitle, among: activeMeetings.map(\.title))
        let note = MeetingNote(title: deduped, recordingMode: .voiceNote, template: .general, spaceID: spaceID)
        meetings.insert(note, at: 0)
        rebuildIndexMap()
        selectedMeetingID = note.id
        invalidateCaches()
        saveMeeting(id: note.id)
        return note
    }

    func updateMeeting(_ meeting: MeetingNote) {
        guard let index = meetingIndex(for: meeting.id) else { return }
        var updated = meeting
        updated.modifiedAt = Date()
        meetings[index] = updated
        invalidateCaches()
        saveMeeting(id: meeting.id)
    }

    /// Update the text of a single transcript segment.
    func updateSegmentText(meetingID: UUID, segmentID: UUID, text: String) {
        guard let mIdx = meetingIndex(for: meetingID),
              let sIdx = meetings[mIdx].segments.firstIndex(where: { $0.id == segmentID })
        else { return }
        meetings[mIdx].segments[sIdx].text = text
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    /// Reassign a transcript segment to a different speaker.
    func reassignSegmentSpeaker(meetingID: UUID, segmentID: UUID, newSpeakerLabel: String?) {
        guard let mIdx = meetingIndex(for: meetingID),
              let sIdx = meetings[mIdx].segments.firstIndex(where: { $0.id == segmentID })
        else { return }
        meetings[mIdx].segments[sIdx].speakerLabel = newSpeakerLabel
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    /// Update only the chat messages for a meeting (avoids overwriting other fields).
    func setChatMessages(_ messages: [MeetingChatMessage], for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].chatMessages = messages
        scheduleMetadataSave(for: meetingID)
    }

    func deleteMeeting(id: UUID) {
        guard let index = meetingIndex(for: id) else { return }
        meetings[index].isTrashed = true
        meetings[index].trashedAt = Date()
        meetings[index].spaceID = nil
        if selectedMeetingID == id {
            selectedMeetingID = nil
        }
        invalidateCaches()
        saveMeeting(id: id)
        MeetingMemoryIndex.shared.removeMeeting(id: id)
    }

    /// B18: Renamed from deleteMeetingWithUndo — this is a soft-delete (trash), not undo.
    func trashMeeting(id: UUID) {
        deleteMeeting(id: id)
    }

    func restoreMeeting(id: UUID) {
        guard let index = meetingIndex(for: id) else { return }
        meetings[index].isTrashed = false
        meetings[index].trashedAt = nil
        invalidateCaches()
        saveMeeting(id: id)
        MeetingMemoryIndex.shared.indexMeeting(meetings[index])
    }

    func permanentlyDeleteMeeting(id: UUID) {
        let audioURL = meetings.first { $0.id == id }?.audioFileURL
        meetings.removeAll { $0.id == id }
        rebuildIndexMap()
        if selectedMeetingID == id {
            selectedMeetingID = nil
        }
        invalidateCaches()
        deleteMeetingFile(id: id)
        if let audioURL {
            Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        MeetingMemoryIndex.shared.removeMeeting(id: id)
    }

    func trashMeetings(inSpace spaceID: UUID) {
        var trashedIDs: [UUID] = []
        for index in meetings.indices where meetings[index].spaceID == spaceID && !meetings[index].isTrashed {
            meetings[index].isTrashed = true
            meetings[index].trashedAt = Date()
            meetings[index].spaceID = nil
            trashedIDs.append(meetings[index].id)
            MeetingMemoryIndex.shared.removeMeeting(id: meetings[index].id)
        }
        if let sel = selectedMeetingID, meetings.first(where: { $0.id == sel })?.isTrashed == true {
            selectedMeetingID = nil
        }
        invalidateCaches()
        for id in trashedIDs {
            saveMeeting(id: id)
        }
    }

    func emptyMeetingTrash() {
        let trashedIDs = meetings.filter(\.isTrashed).map(\.id)
        meetings.removeAll(where: \.isTrashed)
        rebuildIndexMap()
        invalidateCaches()
        for id in trashedIDs {
            deleteMeetingFile(id: id)
        }
    }

    func renameMeeting(id: UUID, newTitle: String) {
        guard let index = meetingIndex(for: id) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let otherTitles = activeMeetings.filter { $0.id != id }.map(\.title)
        meetings[index].title = uniqueTitle(trimmed, among: otherTitles)
        meetings[index].modifiedAt = Date()
        invalidateCaches()
        scheduleMetadataSave(for: id)
    }

    func togglePin(id: UUID) {
        guard let index = meetingIndex(for: id) else { return }
        meetings[index].isPinned.toggle()
        invalidateCaches()
        scheduleMetadataSave(for: id)
    }

    func toggleArchive(id: UUID) {
        guard let index = meetingIndex(for: id) else { return }
        meetings[index].isArchived.toggle()
        invalidateCaches()
        scheduleMetadataSave(for: id)
    }

    // MARK: - Space Operations

    func meetings(inSpace spaceID: UUID) -> [MeetingNote] {
        meetings.filter { $0.spaceID == spaceID && !$0.isTrashed }
    }

    func moveMeeting(id: UUID, toSpace spaceID: UUID?) {
        guard let index = meetingIndex(for: id) else { return }
        meetings[index].spaceID = spaceID
        meetings[index].modifiedAt = Date()
        invalidateCaches()
        scheduleMetadataSave(for: id)
    }

    func unfileMeetings(inSpace spaceID: UUID) {
        var updatedIDs: [UUID] = []
        for index in meetings.indices where meetings[index].spaceID == spaceID {
            meetings[index].spaceID = nil
            updatedIDs.append(meetings[index].id)
        }
        invalidateCaches()
        for id in updatedIDs {
            saveMeeting(id: id)
        }
    }

    /// Per-meeting debounced saves for non-critical metadata changes (favorite, archive, rename).
    private var metadataSaveTasks: [UUID: Task<Void, Never>] = [:]

    private func scheduleMetadataSave(for meetingID: UUID) {
        metadataSaveTasks[meetingID]?.cancel()
        metadataSaveTasks[meetingID] = Task {
            try? await Task.sleep(for: AppConstants.Delays.metadataSaveDebounce)
            guard !Task.isCancelled else {
                metadataSaveTasks.removeValue(forKey: meetingID)
                return
            }
            saveMeeting(id: meetingID)
            metadataSaveTasks.removeValue(forKey: meetingID)
        }
        // Prune completed/cancelled tasks to prevent unbounded dictionary growth
        if metadataSaveTasks.count > 100 {
            metadataSaveTasks = metadataSaveTasks.filter { !$0.value.isCancelled }
        }
    }

    // MARK: - Transcript Mutations

    /// Append a segment. During live recording, pass `persistImmediately: false`
    /// to avoid blocking the main thread on every chunk. Call `saveMeeting(id:)` manually
    /// when recording stops.
    func appendSegment(_ segment: TranscriptSegment, to meetingID: UUID, persistImmediately: Bool = true) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].segments.append(segment)
        meetings[index].modifiedAt = Date()
        if persistImmediately {
            saveMeeting(id: meetingID)
        } else {
            scheduleDebouncedSave(for: meetingID)
        }

        // Auto-generate title once when enough transcript content arrives
        if !hasTriggeredAutoTitle[meetingID, default: false],
           isDefaultTitle(meetings[index].title)
        {
            let charCount = meetings[index].segments.reduce(0) { $0 + $1.text.trimmingCharacters(in: .whitespacesAndNewlines).count }
            if charCount > 50 {
                logger.info("Auto-title triggered for meeting \(meetingID) (\(charCount) chars)")
                hasTriggeredAutoTitle[meetingID] = true
                titleGenerationTask?.cancel()
                titleGenerationTask = Task {
                    try? await Task.sleep(for: AppConstants.Delays.meetingAutoTitleDebounce)
                    guard !Task.isCancelled else {
                        logger.warning("Auto-title task cancelled for meeting \(meetingID)")
                        return
                    }
                    await generateAITitle(for: meetingID)
                }
            }
        }
    }

    /// Merge mic transcript segments (from Pass 2) into the meeting timeline, sorted by startTime.
    func mergeMicSegments(_ micSegments: [TranscriptSegment], into meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].segments.append(contentsOf: micSegments)
        meetings[index].segments.sort { $0.startTime < $1.startTime }
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    private var debouncedSaveTask: Task<Void, Never>?

    /// B4: Save to disk at most once every 3 seconds during live recording.
    /// Cancels any pending save and restarts the debounce window.
    private func scheduleDebouncedSave(for meetingID: UUID) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task {
            try? await Task.sleep(for: AppConstants.Delays.liveRecordingSaveDebounce)
            guard !Task.isCancelled else { return }
            saveMeeting(id: meetingID)
            debouncedSaveTask = nil
        }
    }

    func updateDuration(_ duration: TimeInterval, for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].duration = duration
        saveMeeting(id: meetingID)
    }

    func setAudioFileURL(_ url: URL, for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].audioFileURL = url
        saveMeeting(id: meetingID)
    }

    // MARK: - Speaker Diarization (see MeetingStore+Diarization.swift)

    func setSummary(_ summary: String, for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].summary = summary
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
        MeetingMemoryIndex.shared.indexMeeting(meetings[index])
    }

    func setSmartMinutes(_ minutes: SmartMinutes, for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].smartMinutes = minutes
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
        MeetingMemoryIndex.shared.indexMeeting(meetings[index])
    }

    func setActionItems(_ items: [ActionItem], for meetingID: UUID) {
        guard let index = meetingIndex(for: meetingID) else { return }
        meetings[index].actionItems = items
        meetings[index].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func toggleActionItemCompleted(itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }
        meetings[mIdx].actionItems[itemIndex].isCompleted.toggle()
        meetings[mIdx].modifiedAt = Date()

        // Cancel reminder when marking complete
        if meetings[mIdx].actionItems[itemIndex].isCompleted,
           let notifID = meetings[mIdx].actionItems[itemIndex].notificationID
        {
            ReminderManager.shared.cancelReminder(notificationID: notifID)
            meetings[mIdx].actionItems[itemIndex].reminderDate = nil
            meetings[mIdx].actionItems[itemIndex].notificationID = nil
        }

        saveMeeting(id: meetingID)
    }

    // MARK: - Action Item Due Date & Reminders

    func setActionItemDueDate(_ dueDate: Date?, itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }
        meetings[mIdx].actionItems[itemIndex].dueDate = dueDate
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func setActionItemReminder(itemID: UUID, in meetingID: UUID, reminderDate: Date) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }

        let item = meetings[mIdx].actionItems[itemIndex]
        let meetingTitle = meetings[mIdx].title

        // Cancel existing reminder if any
        if let existingNotifID = item.notificationID {
            ReminderManager.shared.cancelReminder(notificationID: existingNotifID)
        }

        // Schedule new reminder
        let notifID = ReminderManager.shared.scheduleReminder(
            for: item,
            at: reminderDate,
            meetingTitle: meetingTitle
        )

        meetings[mIdx].actionItems[itemIndex].reminderDate = reminderDate
        meetings[mIdx].actionItems[itemIndex].notificationID = notifID
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }

    func cancelActionItemReminder(itemID: UUID, in meetingID: UUID) {
        guard let mIdx = meetingIndex(for: meetingID),
              let itemIndex = meetings[mIdx].actionItems.firstIndex(where: { $0.id == itemID })
        else { return }

        if let notifID = meetings[mIdx].actionItems[itemIndex].notificationID {
            ReminderManager.shared.cancelReminder(notificationID: notifID)
        }

        meetings[mIdx].actionItems[itemIndex].reminderDate = nil
        meetings[mIdx].actionItems[itemIndex].notificationID = nil
        meetings[mIdx].modifiedAt = Date()
        saveMeeting(id: meetingID)
    }
}

// MARK: - Extension Files

//
// MeetingStore+AI.swift           — AI title, summary, and space suggestion generation
// MeetingStore+Diarization.swift  — Speaker diarization data and transcript label assignment
// MeetingStore+Metadata.swift     — Bookmarks, tags
// MeetingStore+Persistence.swift  — File I/O: save, load, delete, bulk operations, digest cache
// MeetingStore+Search.swift       — Full-text search, snippet extraction, topic keywords, related meetings
// MeetingStore+SeedData.swift     — Sample meeting data for first launch
// MeetingStore+WelcomeMeeting.swift — Welcome/onboarding meeting seed
// MeetingStoreProtocols.swift     — Protocol facades for testability
