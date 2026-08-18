import SwiftUI

// MARK: - Navigation

/// Back and breadcrumb navigation for the main window.
///
/// Split out of `MainWindowView` to keep that type within the project's body-length
/// limit; the members it touches are marked `// Extension-visible: +Navigation`.
extension MainWindowView {
    func handleBreadcrumbClick(_ segment: BreadcrumbSegment) {
        guard let item = segment.sidebarItem else { return }

        // The first segment reads "Back" when the source is itself a document or
        // meeting — which happens after following a link. Clearing the editing state
        // for those would leave an empty pane, because the content area only renders
        // a document while editing. Navigate to them instead.
        switch item {
        case .document, .meeting:
            navigateToContentBreadcrumb(item)
            return
        default:
            break
        }

        // Choosing a list from the sidebar abandons the link trail deliberately, so the trail must
        // not survive it: `clear()` had no callers at all, which meant Back could jump to a document
        // the user had left several navigations ago instead of to the list they were looking at.
        NavigationHistory.shared.clear()

        storeChangeVersion += 1
        withAnimation(.easeOut(duration: 0.08)) {
            isEditing = false
            store.selectedDocumentID = nil
            meetingStore.selectedMeetingID = nil
        }
        sidebarSelection = item
    }

    /// Opens a document/meeting breadcrumb, preferring the link trail so a chain of
    /// followed links unwinds one step at a time.
    func navigateToContentBreadcrumb(_ item: SidebarItem) {
        // Bumped only when something is actually going to change the selection. Incrementing first
        // and then finding nothing to do left the counter ahead of `lastSeenStoreVersion`, and the
        // version guard swallowed the *next* real sidebar click. CLAUDE.md says to sync the counter
        // in the handler that increments it, which is what the guard in `MainWindowView` does — so
        // the increment has to be truthful.
        if ContentNavigator.goBack() {
            storeChangeVersion += 1
            return
        }

        switch item {
        case let .document(id):
            if ContentNavigator.open(.document(id: id), recordHistory: false) {
                storeChangeVersion += 1
            }
        case let .meeting(id):
            if ContentNavigator.open(.meeting(id: id), recordHistory: false) {
                storeChangeVersion += 1
            }
        default:
            break
        }
    }

    // MARK: - Navigation

    func goBack() {
        // A link trail takes priority: after following a link, Back should return to
        // the document you clicked from, not to a list.
        if ContentNavigator.goBack() {
            return
        }

        // `editingSourceSelection` can itself be a document or meeting — when a link
        // changed the selection while already editing. Falling back to it here would
        // set the sidebar to an item while clearing the editing state, leaving an
        // empty pane, so resolve those to their list instead.
        let destination = listDestination(for: editingSourceSelection)
        // Mark as store-driven so sidebar onChange doesn't re-process
        storeChangeVersion += 1
        withAnimation(.easeOut(duration: 0.08)) {
            isEditing = false
            store.selectedDocumentID = nil
            meetingStore.selectedMeetingID = nil
        }
        sidebarSelection = destination
    }

    /// A destination that renders something on its own. Document and meeting items
    /// only render while editing, so they are not valid Back targets.
    func listDestination(for item: SidebarItem?) -> SidebarItem {
        switch item {
        case .document: .allDocuments
        case .meeting: .allMeetings
        case let .some(other): other
        case nil: .home
        }
    }
}
