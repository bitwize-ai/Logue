import Foundation

/// Observable busy state for the LLM inference engine.
///
/// UI views observe `isBusy` to disable AI controls while an inference
/// operation is in progress, preventing concurrent session access that
/// causes intermittent crashes from actor reentrancy.
@MainActor @Observable
final class LLMEngineStatus {
    static let shared = LLMEngineStatus()
    private init() {}

    /// Whether an inference operation is currently running.
    private(set) var isBusy = false

    func setBusy(_ busy: Bool) {
        isBusy = busy
    }
}
