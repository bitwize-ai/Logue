import Foundation

/// Reading the workspace into the shape `HomeSuggestions.chips(for:)` wants.
///
/// Kept out of `HomeSuggestions.swift` so that file stays pure — the rules there are
/// testable precisely because they touch no store. This is the other half: which stores the
/// inputs come from, stated once.
///
/// It was three private computed properties inside `AgentChatView`, which is why the island
/// had no starters at all. Copying them would have been the easy version and the wrong one:
/// `workspaceIsEmpty` alone spans three stores, and a second copy that forgot spaces would
/// offer a returning user the first-run chips.
extension HomeSuggestions {
    /// Whether every store the chips depend on has finished loading.
    ///
    /// Greeting a returning user as a new one because their library was still being read is
    /// the loudest wrong answer this can give, so nothing renders until all three report.
    @MainActor
    static var storesAreLoaded: Bool {
        DocumentStore.shared.isLoaded
            && MeetingStore.shared.isLoaded
            && SpaceStore.shared.isLoaded
    }

    /// The workspace as the chip rules see it.
    ///
    /// - Parameter overdueCount: from `InsightsStatsProvider`, which each surface owns; it is
    ///   derived rather than stored, so it is passed in rather than read from a fourth store.
    @MainActor
    static func currentInputs(overdueCount: Int) -> Inputs {
        let meetings = MeetingStore.shared.activeMeetings
        let unsummarized = meetings
            .filter { ($0.summary ?? "").isEmpty && !$0.isArchived }
            .max { $0.createdAt < $1.createdAt }

        // One definition of "empty", used by every surface. Two definitions is how a
        // workspace with spaces but no documents gets first-run chips.
        let isEmpty = DocumentStore.shared.activeDocuments.isEmpty
            && meetings.isEmpty
            && SpaceStore.shared.topLevelSpaces.isEmpty

        return Inputs(
            unsummarizedMeetingTitle: unsummarized?.title,
            overdueCount: overdueCount,
            meetingsToday: MeetingStore.shared.todaysMeetings.count,
            hasAnyContent: !isEmpty
        )
    }
}
