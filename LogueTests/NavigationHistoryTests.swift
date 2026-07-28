import Foundation
@testable import Logue
import Testing

@Suite("NavigationHistory")
@MainActor
struct NavigationHistoryTests {
    private let alpha = NavigationTarget.document(id: UUID())
    private let beta = NavigationTarget.document(id: UUID())
    private let standup = NavigationTarget.meeting(id: UUID())

    @Test("A fresh history cannot go back")
    func freshHistory() {
        #expect(NavigationHistory().canGoBack == false)
        #expect(NavigationHistory().popPrevious() == nil)
    }

    @Test("Pushing one entry allows going back to it")
    func pushThenPop() {
        let history = NavigationHistory()
        history.push(alpha)
        #expect(history.canGoBack)
        #expect(history.popPrevious() == alpha)
    }

    @Test("Popping removes the entry, so back does not repeat")
    func popRemoves() {
        let history = NavigationHistory()
        history.push(alpha)
        _ = history.popPrevious()
        #expect(history.canGoBack == false)
    }

    @Test("Entries pop in reverse order")
    func reverseOrder() {
        let history = NavigationHistory()
        history.push(alpha)
        history.push(beta)
        #expect(history.popPrevious() == beta)
        #expect(history.popPrevious() == alpha)
        #expect(history.popPrevious() == nil)
    }

    @Test("Documents and meetings share one history")
    func mixedKinds() {
        let history = NavigationHistory()
        history.push(alpha)
        history.push(standup)
        #expect(history.popPrevious() == standup)
        #expect(history.popPrevious() == alpha)
    }

    @Test("Pushing the same target twice in a row records it once")
    func consecutiveDuplicatesCollapsed() {
        let history = NavigationHistory()
        history.push(alpha)
        history.push(alpha)
        #expect(history.popPrevious() == alpha)
        #expect(history.canGoBack == false)
    }

    @Test("The same target is recorded again when something else came between")
    func nonConsecutiveDuplicatesKept() {
        let history = NavigationHistory()
        history.push(alpha)
        history.push(beta)
        history.push(alpha)
        #expect(history.popPrevious() == alpha)
        #expect(history.popPrevious() == beta)
        #expect(history.popPrevious() == alpha)
    }

    @Test("History depth is bounded, dropping the oldest entries")
    func boundedDepth() {
        let history = NavigationHistory()
        let targets = (0 ..< (NavigationHistory.maxDepth + 10)).map { _ in
            NavigationTarget.document(id: UUID())
        }
        for target in targets {
            history.push(target)
        }
        #expect(history.depth == NavigationHistory.maxDepth)
        // The most recent push is still the first one back.
        #expect(history.popPrevious() == targets.last)
    }

    @Test("Clearing empties the history")
    func clearing() {
        let history = NavigationHistory()
        history.push(alpha)
        history.clear()
        #expect(history.canGoBack == false)
    }

    @Test("Space targets are not recorded, since they cannot be navigated to")
    func spacesNotRecorded() {
        let history = NavigationHistory()
        history.push(.space(id: UUID()))
        #expect(history.canGoBack == false)
    }
}

/// What `goBack()` reports, which decides whether the caller falls back to its own behaviour.
///
/// Reporting success when nothing happened made the Back button dead: the caller trusted the
/// boolean and skipped its list fallback. It also left a version counter ahead, which swallowed the
/// next sidebar click.
@Suite("Navigation history reporting")
@MainActor
struct NavigationHistoryReportingTests {
    private func withEmptyHistory(_ body: () -> Void) {
        NavigationHistory.shared.clear()
        body()
        NavigationHistory.shared.clear()
    }

    @Test("Back reports failure when there is nothing to go back to")
    func emptyHistoryReportsFailure() {
        withEmptyHistory {
            #expect(ContentNavigator.goBack() == false)
        }
    }

    /// The reviewer's repro: follow a link, then permanently delete what you came from.
    @Test("Back reports failure when the entry no longer resolves")
    func unresolvableEntryReportsFailure() {
        withEmptyHistory {
            NavigationHistory.shared.push(.document(id: UUID()))

            #expect(ContentNavigator.goBack() == false)
        }
    }

    /// And it must not stick: a target that cannot resolve now will not resolve next time either.
    @Test("An unresolvable entry is dropped rather than retried forever")
    func unresolvableEntryIsDropped() {
        withEmptyHistory {
            NavigationHistory.shared.push(.document(id: UUID()))
            _ = ContentNavigator.goBack()

            #expect(NavigationHistory.shared.depth == 0)
        }
    }

    @Test("Clearing empties the trail")
    func clearEmptiesTheTrail() {
        withEmptyHistory {
            NavigationHistory.shared.push(.document(id: UUID()))
            NavigationHistory.shared.push(.meeting(id: UUID()))
            #expect(NavigationHistory.shared.depth == 2)

            NavigationHistory.shared.clear()
            #expect(NavigationHistory.shared.depth == 0)
        }
    }
}
