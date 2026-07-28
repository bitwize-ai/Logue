import Foundation

/// Back history for link navigation.
///
/// Records where you came from when a link takes you somewhere, so Back returns to
/// the document you clicked from rather than to a list — which is what people expect
/// after following a link.
///
/// Only link navigation is recorded. Sidebar and list selections are not: those
/// already have their own back behaviour, and mixing the two would make Back
/// unpredictable.
@MainActor
@Observable
final class NavigationHistory {
    static let shared = NavigationHistory()

    /// Cap on remembered entries. Deep enough for any real trail of links, bounded so
    /// a long session cannot grow it without limit.
    static let maxDepth = 50

    private var stack: [NavigationTarget] = []

    var canGoBack: Bool {
        !stack.isEmpty
    }

    var depth: Int {
        stack.count
    }

    /// Records a place to come back to.
    ///
    /// Consecutive duplicates collapse, so re-opening the document you are already on
    /// does not add a Back step that appears to do nothing. Spaces are skipped
    /// because there is nothing to navigate back to.
    func push(_ target: NavigationTarget) {
        if case .space = target {
            return
        }
        if stack.last == target {
            return
        }

        stack.append(target)
        if stack.count > Self.maxDepth {
            stack.removeFirst(stack.count - Self.maxDepth)
        }
    }

    /// Removes and returns the most recent entry.
    func popPrevious() -> NavigationTarget? {
        stack.popLast()
    }

    func clear() {
        stack.removeAll()
    }
}
