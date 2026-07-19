import Foundation
import LocalAuthentication
import os.log

/// Serializes user-approval flow for destructive agent tool calls.
///
/// The graph's `execute_tools` node calls `awaitDecision(toolCallID:)` before running any
/// tool whose `ToolClearance` requires approval. The UI resolves the gate by calling
/// `approve(toolCallID:clearance:)` or `reject(toolCallID:)`. For `.dangerous` clearance,
/// `approve(...)` first runs a `LAContext.evaluatePolicy` biometric check — if the check
/// fails, the gate auto-rejects. If the user doesn't respond within
/// `AppConstants.AgentDefaults.approvalTimeoutSeconds`, the gate auto-resolves as `.timedOut`
/// so the agent isn't left waiting forever.
actor ApprovalGate {
    static let shared = ApprovalGate()
    private init() {}

    enum Decision {
        case approved
        case rejected
        case timedOut
    }

    /// One outstanding gate. Pairs the awaiting continuation with the timeout
    /// task so resolution can cancel the timeout *before* resuming, eliminating
    /// the double-resume race that the old `defer { timeoutTask.cancel() }`
    /// pattern had.
    private struct Pending {
        let continuation: CheckedContinuation<Decision, Never>
        let timeoutTask: Task<Void, Never>
    }

    private var pending: [UUID: Pending] = [:]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "ApprovalGate")

    /// Suspends until the user approves, rejects, or the timeout elapses.
    /// Safe to call concurrently — each call is keyed by `toolCallID`.
    func awaitDecision(toolCallID: UUID) async -> Decision {
        await withCheckedContinuation { cont in
            // Schedule a timeout that races the UI. The task is stored alongside
            // the continuation so `resolve(...)` can cancel it before resuming —
            // any in-flight timeout that has already passed `Task.sleep` is
            // short-circuited by the `pending[toolCallID] != nil` check inside
            // `resolveTimeout`.
            let timeoutTask = Task { [weak self] in
                let seconds = AppConstants.AgentDefaults.approvalTimeoutSeconds
                try? await Task.sleep(for: .seconds(seconds))
                await self?.resolveTimeout(toolCallID: toolCallID)
            }
            pending[toolCallID] = Pending(continuation: cont, timeoutTask: timeoutTask)
        }
    }

    /// Resolves the gate as approved. For `.dangerous` clearance, runs a biometric
    /// (Touch ID / device-owner) check first — if biometric fails or is cancelled,
    /// the gate resolves as `.rejected` instead.
    func approve(toolCallID: UUID, clearance: ToolClearance, toolName: String) async {
        if clearance.requiresBiometric {
            let granted = await Self.runBiometricCheck(toolName: toolName)
            if !granted {
                logger.info("Biometric denied for tool \(toolName, privacy: .public)")
                resolve(toolCallID: toolCallID, decision: .rejected)
                return
            }
        }
        resolve(toolCallID: toolCallID, decision: .approved)
    }

    /// Resolve the gate with user rejection.
    func reject(toolCallID: UUID) {
        resolve(toolCallID: toolCallID, decision: .rejected)
    }

    /// Rejects every outstanding pending approval. Used when the agent turn is cancelled.
    /// Cancels each entry's timeout task so we don't leak background sleeps.
    func rejectAllPending() {
        let outstanding = pending
        pending.removeAll()
        for (_, entry) in outstanding {
            entry.timeoutTask.cancel()
            entry.continuation.resume(returning: .rejected)
        }
    }

    private func resolveTimeout(toolCallID: UUID) {
        guard pending[toolCallID] != nil else { return }
        logger.warning("Approval gate timed out for \(toolCallID)")
        resolve(toolCallID: toolCallID, decision: .timedOut)
    }

    /// Single resolution path for every `Decision`. Cancels the timeout task
    /// *before* resuming the continuation — without this the timeout could fire
    /// after a successful approve/reject and try to resume an already-consumed
    /// continuation, crashing the actor.
    private func resolve(toolCallID: UUID, decision: Decision) {
        guard let entry = pending.removeValue(forKey: toolCallID) else { return }
        entry.timeoutTask.cancel()
        entry.continuation.resume(returning: decision)
    }

    // MARK: - Biometric Check

    /// Performs a Touch ID / device-owner biometric check. Falls back to passcode if
    /// biometrics are unavailable. Returns `true` only if the user successfully
    /// authenticated. Errors and cancellations both return `false`.
    /// Captures `context` in the continuation closure so it stays alive until the
    /// callback fires (otherwise the LAContext could deallocate mid-evaluation).
    private static func runBiometricCheck(toolName: String) async -> Bool {
        let context = LAContext()
        var policyError: NSError?
        // Prefer biometrics; fall back to device password (e.g. Mac without Touch ID).
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &policyError) else {
            // No usable auth method — fail closed rather than silently approving.
            return false
        }

        let reason = "Confirm to allow the agent to run \(toolName)."
        return await withCheckedContinuation { [context] cont in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
    }
}
