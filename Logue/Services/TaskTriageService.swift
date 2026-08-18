import Foundation
import OSLog

/// Runs a triage pass through the shared inference actor.
///
/// Holds no rules of its own — everything that decides what a response *means* lives in
/// `TaskTriage`, which is pure and tested. This type only handles the call and its states.
@MainActor
@Observable
final class TaskTriageService {
    static let shared = TaskTriageService()

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "TaskTriageService")

    private(set) var suggestions: [TriageSuggestion] = []
    private(set) var isRunning = false
    /// How many tasks were actually sent, so a capped review never reads as a complete one.
    private(set) var reviewedCount = 0
    private(set) var lastError: String?

    private init() {}

    func run(tasks: [TaskItem], knownTags: [String]) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        let open = tasks.filter { $0.status == .todo }
        reviewedCount = min(open.count, TaskTriage.maxTasks)
        guard reviewedCount > 0 else {
            suggestions = []
            return
        }

        do {
            let response = try await LLMEngine.shared.complete(
                system: TaskTriage.systemPrompt(),
                prompt: TaskTriage.userPrompt(for: open, knownTags: knownTags),
                // Low, because this is classification rather than writing — a creative triage
                // pass is a wrong one.
                temperature: 0.2,
                maxTokens: 1024
            )
            suggestions = TaskTriage.suggestions(from: response, tasks: open)
            // Read into a local first: the logger's interpolation is an autoclosure, so
            // referring to a property inside it needs an explicit `self` that the formatter
            // then flags as redundant. The local satisfies both.
            let produced = suggestions.count
            logger.info("Triage produced \(produced, privacy: .public) suggestion(s)")
        } catch {
            lastError = error.localizedDescription
            suggestions = []
            logger.error("Triage failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismiss(_ suggestion: TriageSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func clear() {
        suggestions = []
        reviewedCount = 0
        lastError = nil
    }
}
