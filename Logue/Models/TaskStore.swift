import Foundation
import OSLog

/// The app's tasks, and every change that can be made to one.
///
/// The rules that matter — what completing a task means, what capturing text produces — are
/// `static` pure functions, so they are testable without a store, a filesystem or a running
/// app. The instance methods are thin wrappers that persist the result.
@MainActor
@Observable
final class TaskStore {
    static let shared = TaskStore()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "TaskStore")

    private(set) var tasks: [TaskItem] = []

    private init() {
        // Deferred rather than inline, matching `DocumentStore`: reading the folder is
        // filesystem work, and `shared` is touched during view construction.
        Task { [weak self] in
            self?.load()
        }
    }

    // MARK: - Pure rules

    /// The task as it should be after the user toggles it.
    ///
    /// A repeating task does **not** produce a second task: the same one is rewritten, still
    /// open, with its due date advanced. The advance is measured from the old **due date**,
    /// not from today, so a weekly task completed three days late stays on its original
    /// weekday instead of drifting later every cycle.
    ///
    /// Reopening an already-done task does not advance again — otherwise an accidental
    /// double-click would push the task another cycle into the future.
    /// `nonisolated` because it touches nothing on the actor: it is a value in and a value
    /// out. Without this the `@MainActor` on the class would isolate it, and the claim that
    /// these rules are testable without a running app would be false.
    nonisolated static func completing(
        _ task: TaskItem, now: Date = .now, calendar: Calendar = .current
    ) -> TaskItem {
        var updated = task
        // `max` so the stamp always moves forward even when a caller passes a `now` that is
        // older than the task — otherwise "did this change?" comparisons read as no-ops.
        updated.updatedAt = max(now, task.updatedAt.addingTimeInterval(1))

        guard task.status == .todo else {
            updated.status = .todo
            return updated
        }

        guard let recurrence = task.recurrence else {
            updated.status = .done
            return updated
        }

        updated.status = .todo
        updated.completedCount += 1
        let base = task.dueDate ?? calendar.startOfDay(for: now)
        updated.dueDate = recurrence.nextDueDate(after: base, calendar: calendar)
        return updated
    }

    /// The tasks a block of captured text describes. `nonisolated` for the same reason as
    /// `completing` — pure, and tested without a store.
    nonisolated static func captured(
        from text: String, now: Date = .now, calendar: Calendar = .current
    ) -> [TaskItem] {
        TaskTextParser.split(text).compactMap { line in
            let parsed = TaskTextParser.parse(line, now: now, calendar: calendar)
            guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return TaskItem(
                title: parsed.title,
                priority: parsed.priority,
                dueDate: parsed.dueDate,
                tags: parsed.tags,
                recurrence: parsed.recurrence,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    // MARK: - Lifecycle

    func load() {
        tasks = TaskStorage.shared.loadTasks().sorted { $0.createdAt < $1.createdAt }
        // Read into a local first: the logger's interpolation is an autoclosure, so referring
        // to a property inside it needs an explicit `self` that the formatter then flags as
        // redundant. The local satisfies both.
        let loaded = tasks.count
        logger.info("Loaded \(loaded, privacy: .public) task(s)")
    }

    /// Replaces the in-memory list, for a storage-mode switch that re-read everything.
    func replaceAll(with tasks: [TaskItem]) {
        self.tasks = tasks.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Mutation

    @discardableResult
    func capture(_ text: String) -> [TaskItem] {
        let created = Self.captured(from: text)
        for task in created {
            add(task)
        }
        return created
    }

    func add(_ task: TaskItem) {
        tasks.append(task)
        TaskStorage.shared.save(task)
    }

    func update(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var stamped = task
        stamped.updatedAt = .now
        tasks[index] = stamped
        TaskStorage.shared.save(stamped)
    }

    func toggleCompletion(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let updated = Self.completing(tasks[index])
        tasks[index] = updated
        TaskStorage.shared.save(updated)
    }

    /// Empties the list and everything behind it, for the "clear data" paths.
    ///
    /// Without this the reset dialogs cleared documents, meetings and spaces while the task
    /// list stayed on screen — and in encrypted mode the tasks survived a full reset entirely.
    func clearAllData() {
        tasks = []
        TaskStorage.shared.clearAllData()
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        TaskStorage.shared.remove(taskID: id)
    }

    // MARK: - Reading

    var openTasks: [TaskItem] {
        tasks.filter { $0.status == .todo }
    }

    func task(id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    /// Every tag in use, for the filter menu and for triage's suggestion vocabulary.
    var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tasks.flatMap(\.tags) where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result.sorted()
    }
}
