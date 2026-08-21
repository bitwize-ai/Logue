import Foundation
import Testing

@testable import Logue

/// Who a Deep Research run belongs to.
///
/// Deep Research is one-at-a-time app-wide, which is exactly what made a single global
/// `isRunning` look sufficient — and why the bug it hides only appears once a second surface
/// can start a run. These cases are the guard on that, and they need no model: ownership is
/// decided by the coordinator's own state, not by the pipeline.
@Suite("DeepResearchOwnership")
@MainActor
struct DeepResearchOwnershipTests {
    /// The coordinator is a singleton, so each case leaves it as it found it.
    ///
    /// `run` spawns a `Task` that would reach for a model. Nothing here is `async` and every
    /// body is synchronous main-actor code, so that task cannot be scheduled before the
    /// `defer` cancels it — the ownership state is set synchronously by `run` itself, which
    /// is the only part these cases look at. Making any of them `async` would hand the
    /// pipeline a turn to start on, so don't.
    private func withIdleCoordinator(_ body: (DeepResearchCoordinator) -> Void) {
        let coordinator = DeepResearchCoordinator.shared
        coordinator.cancel()
        coordinator.dismiss()
        defer {
            coordinator.cancel()
            coordinator.dismiss()
        }
        body(coordinator)
    }

    @Test("An idle coordinator belongs to no conversation")
    func idleOwnsNothing() {
        withIdleCoordinator { coordinator in
            #expect(coordinator.runningConversationID == nil)
            #expect(coordinator.isRunning(in: UUID()) == false)
            #expect(coordinator.hasActivity(in: UUID()) == false)
        }
    }

    @Test("A run is reported only to the conversation that asked for it")
    func onlyTheOwnerSeesTheRun() {
        // The failure this prevents: the island starts a run, and the main window's input bar
        // goes busy and its progress strip appears on whatever thread it happens to be showing.
        withIdleCoordinator { coordinator in
            let island = UUID()
            let mainWindow = UUID()
            coordinator.run(prompt: "why", conversationID: island)

            #expect(coordinator.isRunning(in: island))
            #expect(coordinator.isRunning(in: mainWindow) == false)
            #expect(coordinator.hasActivity(in: mainWindow) == false)
        }
    }

    @Test("Cancelling leaves the failure with its owner and nobody else")
    func cancellationStaysWithTheOwner() {
        // `lastError` outlives the run — the strip has to say why it stopped — so the owner
        // has to outlive it too, or the message paints on every surface.
        withIdleCoordinator { coordinator in
            let owner = UUID()
            let other = UUID()
            coordinator.run(prompt: "why", conversationID: owner)
            coordinator.cancel()

            #expect(coordinator.isRunning == false)
            #expect(coordinator.lastError != nil, "a cancelled run says so")
            #expect(coordinator.hasActivity(in: owner), "and says it here")
            #expect(coordinator.hasActivity(in: other) == false, "not here")
        }
    }

    @Test("A failed run still has something to report")
    func failedRunsStillReport() {
        // The progress strip mounts on `hasActivity`, so this is the predicate that decides
        // whether a user who cancelled sees why it stopped. It used to mount on a separate
        // expression in the view, which meant these assertions could stay green while the
        // strip stopped appearing.
        withIdleCoordinator { coordinator in
            let owner = UUID()
            coordinator.run(prompt: "why", conversationID: owner)
            coordinator.cancel()
            #expect(coordinator.currentStep == .failed)
            #expect(coordinator.hasActivity(in: owner))
        }
    }

    @Test("Dismissing a finished run gives up the thread")
    func dismissReleasesOwnership() {
        withIdleCoordinator { coordinator in
            let owner = UUID()
            coordinator.run(prompt: "why", conversationID: owner)
            coordinator.cancel()
            coordinator.dismiss()

            #expect(coordinator.runningConversationID == nil)
            #expect(coordinator.hasActivity(in: owner) == false)
        }
    }

    @Test("A refused start appends nothing")
    func refusedStartLeavesNoQuestion() {
        // `start` used to append the question and let `run` drop the request, which left the
        // user's question in the thread with nothing that would ever answer it: no spinner
        // (run state is per conversation), no strip (it belongs to the other conversation),
        // no error, and the composer already cleared. Returning nil is what lets the caller
        // put the question back instead.
        withIdleCoordinator { coordinator in
            let first = UUID()
            coordinator.run(prompt: "one", conversationID: first)

            let refused = coordinator.start(prompt: "two", in: UUID())
            #expect(refused == nil)
            #expect(coordinator.runningConversationID == first, "the first run keeps the coordinator")
        }
    }

    @Test("A second run cannot start while one is in flight")
    func oneRunAtATime() {
        // The pre-existing policy, pinned because ownership now depends on it: if a second
        // run could start it would silently take the first one's thread with it.
        withIdleCoordinator { coordinator in
            let first = UUID()
            let second = UUID()
            coordinator.run(prompt: "one", conversationID: first)
            coordinator.run(prompt: "two", conversationID: second)

            #expect(coordinator.runningConversationID == first)
            #expect(coordinator.isRunning(in: second) == false)
        }
    }
}
