import Foundation
import os.log
import UserNotifications

/// Manages scheduled AI tasks — daily digest, meeting prep, auto-summarize, weekly review.
/// Checks every 60 seconds for due tasks and executes them via existing AI generation methods.
@Observable
@MainActor
final class ScheduledTaskManager {
    static let shared = ScheduledTaskManager()

    // Extension-visible: +WeeklyReview
    let logger = Logger(subsystem: AppConstants.bundleID, category: "ScheduledTasks")

    // MARK: - State

    var tasks: [ScheduledTask] = []
    var isRunningTask = false
    var currentTaskType: ScheduledTask.TaskType?
    /// History of task runs with results, newest first. Kept to last 50 entries.
    var runHistory: [TaskRunRecord] = []

    // MARK: - Internals

    private var checkTimer: Timer?
    /// Tracks calendar events we've already prepped to avoid duplicates.
    /// Reset daily to prevent unbounded growth over months of use.
    private var preppedEventIDs: Set<String> = []
    private var preppedEventIDsResetDate: Date = .distantPast
    private static let maxHistoryEntries = 50

    private static let storageURL: URL = {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory)
            .appendingPathComponent("Logue")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            os_log(.error, "Failed to create ScheduledTaskManager storage directory: %{public}@", error.localizedDescription)
        }
        return dir.appendingPathComponent("scheduled_tasks.json")
    }()

    private static let historyURL: URL = {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory)
            .appendingPathComponent("Logue")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            os_log(.error, "Failed to create ScheduledTaskManager history directory: %{public}@", error.localizedDescription)
        }
        return dir.appendingPathComponent("task_run_history.json")
    }()

    // Bug-5: Track loaded state to prevent scheduler race
    private(set) var isLoaded = false

    // C-N2: Move sync I/O off MainActor init
    private init() {
        Task {
            await loadFromDiskAsync()
            ensureDefaultTasks()
            isLoaded = true
        }
    }

    private func loadFromDiskAsync() async {
        let tasksURL = Self.storageURL
        let histURL = Self.historyURL
        let (loadedTasks, loadedHistory) = await Task.detached(priority: .utility) {
            var loadedTasks: [ScheduledTask]?
            var loadedHistory: [TaskRunRecord]?
            if FileManager.default.fileExists(atPath: tasksURL.path()) {
                if let data = try? Data(contentsOf: tasksURL) {
                    loadedTasks = try? EncryptionManager.decryptCodableWithFallback([ScheduledTask].self, from: data)
                }
            }
            let histPath = histURL.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: histPath) {
                if let data = try? Data(contentsOf: histURL) {
                    loadedHistory = try? EncryptionManager.decryptCodableWithFallback([TaskRunRecord].self, from: data)
                }
            }
            return (loadedTasks, loadedHistory)
        }.value
        if let loadedTasks {
            tasks = loadedTasks
        }
        if let loadedHistory {
            runHistory = loadedHistory
        }
    }

    // MARK: - Scheduler Control

    // B15: Track check task for cancellation on stop
    private var checkTask: Task<Void, Never>?

    func startScheduler() {
        guard checkTimer == nil else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.prunePreppedEventIDs()
                await self?.checkAndRunDueTasks()
            }
        }
        logger.info("Scheduler started")

        // Run an immediate check
        checkTask = Task { await checkAndRunDueTasks() }
    }

    /// Reset prepped event IDs once per day to prevent unbounded memory growth.
    private func prunePreppedEventIDs() {
        if !Calendar.current.isDateInToday(preppedEventIDsResetDate) {
            preppedEventIDs.removeAll()
            preppedEventIDsResetDate = Date()
        }
    }

    func stopScheduler() {
        checkTimer?.invalidate()
        checkTimer = nil
        checkTask?.cancel()
        checkTask = nil
        logger.info("Scheduler stopped")
    }

    // MARK: - Task Management

    func updateTask(_ task: ScheduledTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveToDisk()
        }
    }

    func setEnabled(_ enabled: Bool, for taskID: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].isEnabled = enabled
            saveToDisk()
        }
    }

    // MARK: - Manual Trigger

    /// Runs a task immediately regardless of schedule. Used by "Run Now" buttons in settings.
    /// Requires the model to be loaded. No-op if a task is already running.
    func runTaskManually(taskID: UUID) async {
        guard !isRunningTask else {
            logger.info("Manual run ignored — another task is in progress")
            return
        }
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        guard await LLMEngine.shared.isModelLoaded else {
            logger.info("Manual run skipped — model not loaded")
            return
        }
        await runAndRecord(task, at: .now)
    }

    // MARK: - Due Task Check

    private func checkAndRunDueTasks() async {
        guard isLoaded else { return }
        guard !isRunningTask else { return }
        guard await LLMEngine.shared.isModelLoaded else { return }

        let now = Date.now
        let cal = Calendar.current

        // Bug-6: Snapshot task IDs before await to prevent stale index access
        let taskSnapshot = tasks.enumerated().filter(\.element.isEnabled)
        for (_, task) in taskSnapshot {
            switch task.taskType {
            case .dailyDigest:
                if isDailyTaskDue(task, now: now, calendar: cal) {
                    await runAndRecord(task, at: now)
                }

            case .autoSummarize:
                if isDailyTaskDue(task, now: now, calendar: cal) {
                    await runAndRecord(task, at: now)
                }

            case .weeklyReview:
                if isWeeklyTaskDue(task, now: now, calendar: cal) {
                    await runAndRecord(task, at: now)
                }

            case .meetingPrep:
                await checkMeetingPrepTriggers(task: task, now: now)
            }
        }
    }

    /// Executes a scheduled task and updates its lastRunAt timestamp.
    private func runAndRecord(_ task: ScheduledTask, at now: Date) async {
        await runTask(task)
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].lastRunAt = now
            saveToDisk()
        }
    }

    private func isDailyTaskDue(_ task: ScheduledTask, now: Date, calendar: Calendar) -> Bool {
        // Already ran today?
        if let lastRun = task.lastRunAt, calendar.isDateInToday(lastRun) {
            return false
        }
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        // Use a 30-minute window after the scheduled time so the task still runs
        // if the app launches slightly after the exact minute.
        let scheduledMinutes = task.hour * 60 + task.minute
        let currentMinutes = hour * 60 + minute
        return currentMinutes >= scheduledMinutes && currentMinutes <= scheduledMinutes + 30
    }

    private func isWeeklyTaskDue(_ task: ScheduledTask, now: Date, calendar: Calendar) -> Bool {
        guard let targetDay = task.dayOfWeek else { return false }

        // Already ran this week?
        if let lastRun = task.lastRunAt, calendar.isDate(lastRun, equalTo: now, toGranularity: .weekOfYear) {
            return false
        }

        let currentDay = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        // Bug-4: Use 30-minute window (matching daily tasks) instead of exact-minute check
        guard currentDay == targetDay else { return false }
        let scheduledMinutes = task.hour * 60 + task.minute
        let currentMinutes = hour * 60 + minute
        return currentMinutes >= scheduledMinutes && currentMinutes <= scheduledMinutes + 30
    }

    private func checkMeetingPrepTriggers(task: ScheduledTask, now: Date) async {
        let calendarManager = CalendarManager.shared
        guard calendarManager.isAuthorized, calendarManager.isEnabled else { return }

        let minutesBefore = task.minutesBefore ?? 15

        calendarManager.refreshUpcomingEvents()

        for event in calendarManager.upcomingEvents {
            let minutesUntil = event.startDate.timeIntervalSince(now) / 60

            // Trigger when within the prep window and not already prepped
            if minutesUntil > 0, minutesUntil <= Double(minutesBefore),
               !preppedEventIDs.contains(event.id)
            {
                preppedEventIDs.insert(event.id)
                await runMeetingPrep(for: event)
            }
        }
    }

    // MARK: - Task Execution

    private func runTask(_ task: ScheduledTask) async {
        isRunningTask = true
        currentTaskType = task.taskType
        logger.info("Running scheduled task: \(task.taskType.rawValue)")

        switch task.taskType {
        case .dailyDigest:
            await runDailyDigest()
        case .autoSummarize:
            await runAutoSummarize()
        case .weeklyReview:
            await runWeeklyReview()
        case .meetingPrep:
            break // Handled by checkMeetingPrepTriggers
        }

        isRunningTask = false
        currentTaskType = nil
    }

    // MARK: - Run History

    private func addRecord(_ record: TaskRunRecord) {
        runHistory.insert(record, at: 0)
        if runHistory.count > Self.maxHistoryEntries {
            runHistory = Array(runHistory.prefix(Self.maxHistoryEntries))
        }
        saveHistoryToDisk()
    }

    /// Returns history records filtered by task type.
    func history(for taskType: ScheduledTask.TaskType) -> [TaskRunRecord] {
        runHistory.filter { $0.taskType == taskType }
    }

    /// Clear all run history.
    func clearHistory() {
        runHistory.removeAll()
        saveHistoryToDisk()
    }

    // MARK: - Daily Digest

    private func runDailyDigest() async {
        let store = MeetingStore.shared
        let cal = Calendar.current
        let todaysMeetings = store.activeMeetings.filter { meeting in
            cal.isDateInToday(meeting.createdAt) && !meeting.isArchived && meeting.summary != nil
        }

        guard !todaysMeetings.isEmpty else {
            logger.info("Daily digest: no meetings with summaries today")
            addRecord(TaskRunRecord(
                taskType: .dailyDigest, status: .noContent,
                resultSummary: "No meetings with summaries today."
            ))
            return
        }

        do {
            let raw = try await generateDigestRaw(from: todaysMeetings)
            if let digest = parseDigestJSON(raw) {
                store.cachedDigest = digest
                store.digestMeetingIDs = Set(todaysMeetings.map(\.id))
                store.saveDigestCache()
                sendNotification(title: "Daily Digest Ready", body: digest.headline)
                addRecord(TaskRunRecord(
                    taskType: .dailyDigest, status: .success,
                    resultSummary: digest.headline
                ))
            } else {
                addRecord(TaskRunRecord(
                    taskType: .dailyDigest, status: .failed,
                    resultSummary: "Failed to parse digest from AI response."
                ))
            }
        } catch {
            logger.warning("Scheduled daily digest failed: \(error.localizedDescription, privacy: .public)")
            addRecord(TaskRunRecord(
                taskType: .dailyDigest, status: .failed,
                resultSummary: "Error: \(error.localizedDescription)"
            ))
        }
    }

    private func generateDigestRaw(from meetings: [MeetingNote]) async throws -> String {
        // S9: Cap total context length to prevent memory exhaustion
        let maxContextLength = 4000
        var meetingContext = ""
        for (index, meeting) in meetings.enumerated() {
            let pending = meeting.actionItems.filter { !$0.isCompleted }.count
            let entry = """
            Meeting \(index + 1): \(meeting.title)
            Summary: \(String((meeting.summary ?? "").prefix(300)))
            Action Items: \(meeting.actionItems.count) total, \(pending) pending
            """
            if meetingContext.count + entry.count > maxContextLength {
                break
            }
            if !meetingContext.isEmpty {
                meetingContext += "\n\n"
            }
            meetingContext += entry
        }

        let totalDuration = meetings.reduce(0.0) { $0 + $1.duration }
        let count = meetings.count
        let totalTime = formatDuration(totalDuration)
            + " across \(count) meeting\(count == 1 ? "" : "s")"

        return try await withRetry {
            let result = try await LLMEngine.shared.complete(
                system: LLMEngine.chatSystemPrompt + """

                \nProduce a concise daily digest as JSON with fields:
                "headline", "totalMeetingTime", "keyHighlights" (array), "pendingActions" (array), "tomorrowFocus".
                Output ONLY valid JSON, no extra text.
                """,
                prompt: """
                Generate a daily digest for today's meetings.

                ---

                SUMMARY:
                Total time: \(totalTime)

                TODAY'S MEETINGS:
                \(meetingContext)
                """,
                maxTokens: 1024
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.emptyResponse
            }
            return result
        }
    }

    private func parseDigestJSON(_ raw: String) -> DailyDigest? {
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}"),
              jsonStart <= jsonEnd,
              let data = String(raw[jsonStart ... jsonEnd]).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(DailyDigest.self, from: data)
    }

    // MARK: - Auto-Summarize

    private func runAutoSummarize() async {
        let store = MeetingStore.shared
        let unsummarized = store.activeMeetings.filter { meeting in
            !meeting.isArchived
                && meeting.summary == nil
                && !meeting.segments.isEmpty
                && meeting.segments.map(\.text).joined().count > 20
        }

        guard !unsummarized.isEmpty else {
            logger.info("Auto-summarize: no unsummarized meetings found")
            addRecord(TaskRunRecord(
                taskType: .autoSummarize,
                status: .noContent,
                resultSummary: "No unsummarized meetings found."
            ))
            return
        }

        logger.info("Auto-summarize: processing \(unsummarized.count) meetings")

        var summarizedCount = 0
        var titles: [String] = []
        for meeting in unsummarized {
            await store.generateAITitle(for: meeting.id)
            await store.generateAISummary(for: meeting.id)
            titles.append(meeting.title)
            summarizedCount += 1
        }

        if summarizedCount > 0 {
            let suffix = summarizedCount == 1 ? "" : "s"
            let body = "\(summarizedCount) meeting\(suffix) summarized."
            sendNotification(title: "Meetings Summarized", body: body)
            let detail = titles.prefix(3).joined(separator: ", ")
            addRecord(TaskRunRecord(
                taskType: .autoSummarize,
                status: .success,
                resultSummary: "\(summarizedCount) meeting\(suffix) summarized: \(detail)"
            ))
        }
    }

    // MARK: - Weekly Review

    private func runWeeklyReview() async {
        let store = MeetingStore.shared
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) else { return }

        let thisWeekMeetings = store.activeMeetings.filter {
            $0.createdAt >= weekAgo && !$0.isArchived
        }

        guard !thisWeekMeetings.isEmpty else {
            logger.info("Weekly review: no meetings this week")
            addRecord(TaskRunRecord(
                taskType: .weeklyReview, status: .noContent,
                resultSummary: "No meetings recorded in the past 7 days."
            ))
            return
        }

        let snapshot = WeeklyReviewSnapshot(meetings: thisWeekMeetings, weekStart: weekAgo, weekEnd: .now)
        let result = await generateAndSaveWeeklyReview(snapshot)
        addRecord(result)
    }

    // MARK: - Meeting Prep

    private func runMeetingPrep(for event: CalendarEvent) async {
        let context = buildMeetingPrepContext(for: event)
        let result = await generateMeetingPrepBriefing(for: event, context: context)
        addRecord(result)
    }

    // MARK: - Notifications

    // Extension-visible: +WeeklyReview
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "scheduled-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    // Extension-visible: +WeeklyReview
    func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Persistence

    private func ensureDefaultTasks() {
        let existingTypes = Set(tasks.map(\.taskType))
        for type in ScheduledTask.TaskType.allCases where !existingTypes.contains(type) {
            tasks.append(.defaultTask(for: type))
        }
        saveToDisk()
    }

    // C9: Move I/O off main thread
    @ObservationIgnored private var _saveTask: Task<Void, Never>?

    func saveToDisk() {
        _saveTask?.cancel()
        let snapshot = tasks
        _saveTask = Task.detached(priority: .utility) {
            do {
                let data = try EncryptionManager.encryptCodable(snapshot)
                try data.write(to: Self.storageURL, options: .atomic)
            } catch {
                await MainActor.run {
                    Logger(subsystem: AppConstants.bundleID, category: "ScheduledTaskManager")
                        .error("Failed to save scheduled tasks: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // Bug-3: Deleted dead loadFromDisk() — replaced by loadFromDiskAsync()

    // MARK: - History Persistence

    @ObservationIgnored private var _historySaveTask: Task<Void, Never>?

    // Bug-3: Move history save off MainActor
    private func saveHistoryToDisk() {
        _historySaveTask?.cancel()
        let snapshot = runHistory
        _historySaveTask = Task.detached(priority: .utility) {
            do {
                let data = try EncryptionManager.encryptCodable(snapshot)
                try data.write(to: Self.historyURL, options: .atomic)
            } catch {
                Logger(subsystem: AppConstants.bundleID, category: "ScheduledTaskManager")
                    .error("Failed to save task history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Bug-3: Deleted dead loadHistoryFromDisk() — replaced by loadFromDiskAsync()
}

// MARK: - Weekly Review Snapshot

/// Aggregated metrics for a 7-day window, used to build the Weekly Review document.
struct WeeklyReviewSnapshot {
    let meetings: [MeetingNote]
    let weekStart: Date
    let weekEnd: Date

    var meetingCount: Int {
        meetings.count
    }

    var totalDuration: TimeInterval {
        meetings.reduce(0) { $0 + $1.duration }
    }

    var pendingItems: [(meeting: String, item: ActionItem)] {
        meetings.flatMap { meeting in
            meeting.actionItems.filter { !$0.isCompleted }.map { (meeting.title, $0) }
        }
    }

    var completedItems: [(meeting: String, item: ActionItem)] {
        meetings.flatMap { meeting in
            meeting.actionItems.filter(\.isCompleted).map { (meeting.title, $0) }
        }
    }

    var overdueItems: [(meeting: String, item: ActionItem)] {
        let now = Date()
        return pendingItems.filter {
            if let due = $0.item.dueDate {
                return due < now
            }
            return false
        }
    }

    var keyDecisions: [(meeting: String, decision: String)] {
        meetings.flatMap { meeting in
            (meeting.smartMinutes?.keyDecisions ?? []).map { (meeting.title, $0) }
        }
    }

    var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: weekEnd))"
    }
}
