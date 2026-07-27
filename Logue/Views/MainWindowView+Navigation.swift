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
        storeChangeVersion += 1
        if ContentNavigator.goBack() {
            return
        }

        switch item {
        case let .document(id):
            ContentNavigator.open(.document(id: id), recordHistory: false)
        case let .meeting(id):
            ContentNavigator.open(.meeting(id: id), recordHistory: false)
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
        case nil: .overview
        }
    }
}
