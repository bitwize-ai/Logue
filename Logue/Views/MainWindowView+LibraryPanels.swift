import SwiftUI

// MARK: - Library panels

/// The panels that live inside All Meetings and All Documents.
///
/// Split out of `MainWindowView` to keep that type within the project's body-length limit.
extension MainWindowView {
    /// What the Action Items panel will show under its default chip.
    ///
    /// Counted through the rule the panel itself uses, so the badge and the list cannot
    /// disagree — this is the signal that used to be a sidebar badge, and the one thing
    /// moving the surface into a panel must not lose.
    var actionItemInboxCount: Int {
        meetingStore.activeMeetings
            .filter { !$0.isArchived }
            .flatMap(\.actionItems)
            .filter {
                ActionItemInbox.matches(
                    $0, mode: .inbox, isPromoted: taskStore.promotedTask(for: $0.id) != nil
                )
            }
            .count
    }

    /// Reveals a library panel, used by the command palette and by launch restoration.
    func open(_ panel: LibraryPanel) {
        switch panel {
        case .actionItems: meetingsPanelCollapsed = false
        case .templates: documentsPanelCollapsed = false
        }
    }
}
