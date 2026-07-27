import Foundation
import OSLog

/// Where a link points.
enum NavigationTarget: Equatable, Sendable {
    case document(id: UUID)
    case meeting(id: UUID)
    case space(id: UUID)
}

/// Resolves link targets and performs the selection.
///
/// One path for every kind of link — `logue://` deep links, `[[wikilinks]]` clicked
/// in the editor, and rows in the Links panel — so navigation behaves identically
/// however it is triggered.
@MainActor
enum ContentNavigator {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "ContentNavigator")

    // MARK: - Resolution

    /// Resolves a wikilink target (bare title or `[[wikilink]]`) to an item.
    ///
    /// Documents are checked before meetings, so a title used by both resolves
    /// deterministically rather than depending on iteration order. Trashed documents
    /// are never targets — a link to something deleted should read as broken.
    nonisolated static func resolve(
        target rawTarget: String,
        documents: [WritingDocument],
        meetings: [MeetingNote]
    ) -> NavigationTarget? {
        let stripped = WikiLinkParser.links(in: rawTarget).first?.target ?? rawTarget
        let key = normalise(stripped)
        guard !key.isEmpty else { return nil }

        if let match = documents.first(where: { !$0.isTrashed && normalise($0.title) == key }) {
            return .document(id: match.id)
        }
        if let match = meetings.first(where: { normalise($0.title) == key }) {
            return .meeting(id: match.id)
        }
        return nil
    }

    nonisolated static func target(for link: DeepLink) -> NavigationTarget {
        switch link {
        case let .document(id): .document(id: id)
        case let .meeting(id): .meeting(id: id)
        case let .space(id): .space(id: id)
        }
    }

    // MARK: - Navigation

    /// The item currently open, if any — the place Back should return to.
    static var currentTarget: NavigationTarget? {
        if let id = DocumentStore.shared.selectedDocumentID {
            return .document(id: id)
        }
        if let id = MeetingStore.shared.selectedMeetingID {
            return .meeting(id: id)
        }
        return nil
    }

    /// Selects the target, recording where we came from so Back can return there.
    static func open(_ target: NavigationTarget, recordHistory: Bool = true) {
        if recordHistory, let origin = currentTarget, origin != target {
            NavigationHistory.shared.push(origin)
            logger.debug("Recorded back entry; depth now \(NavigationHistory.shared.depth)")
        }
        select(target)
    }

    /// Returns to the previous link-navigation target. Returns whether it moved, so
    /// the caller can fall back to its own back behaviour.
    @discardableResult
    static func goBack() -> Bool {
        guard let previous = NavigationHistory.shared.popPrevious() else {
            logger.debug("Back requested but history is empty")
            return false
        }
        logger.debug("Going back; depth now \(NavigationHistory.shared.depth)")
        // Do not re-record: going back is not a new destination.
        select(previous)
        return true
    }

    /// Performs the selection. Unknown identifiers are logged and ignored rather than
    /// clearing the current selection.
    private static func select(_ target: NavigationTarget) {
        switch target {
        case let .document(id):
            guard DocumentStore.shared.documents.contains(where: { $0.id == id }) else {
                logger.warning("Ignored navigation to unknown document")
                return
            }
            DocumentStore.shared.selectedDocumentID = id

        case let .meeting(id):
            guard MeetingStore.shared.meetings.contains(where: { $0.id == id }) else {
                logger.warning("Ignored navigation to unknown meeting")
                return
            }
            MeetingStore.shared.selectedMeetingID = id

        case .space:
            // Space selection lives in sidebar view state, not a store, so there is
            // nothing to set from here. `logue://space/…` therefore parses and
            // raises the window but does not change selection. Wiring it needs a
            // shared space-selection state first.
            logger.info("Space navigation is not supported yet")
        }
    }

    /// Resolves and opens a wikilink target against the live stores.
    /// Returns whether a target was found, so a caller can report a broken link.
    @discardableResult
    static func openWikiLink(target: String) -> Bool {
        guard let resolved = resolve(
            target: target,
            documents: DocumentStore.shared.documents,
            meetings: MeetingStore.shared.meetings
        )
        else { return false }

        open(resolved)
        return true
    }

    // MARK: - Private

    nonisolated private static func normalise(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
