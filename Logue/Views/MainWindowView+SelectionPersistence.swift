import SwiftUI

// MARK: - Sidebar selection persistence

/// Remembering which sidebar surface the window was last on.
///
/// Split out of `MainWindowView` to keep that type within the project's body-length limit.
/// These are `static` and touch nothing on the view, so they carry across cleanly.
///
/// The mapping itself lives in `SidebarSelectionMigration`, which is pure and tested — this
/// file is only the `UserDefaults` edge.
extension MainWindowView {
    /// UserDefaults key for the last-stable sidebar surface. Document and meeting selections
    /// are restored separately via the per-store `selectedDocumentID` / `selectedMeetingID`,
    /// so only coarse surfaces are persisted here.
    private static var lastSidebarKey: String { "MainWindow.lastSidebarSelection" }

    private static var storedSelection: SidebarSelectionMigration.Restored? {
        guard let raw = UserDefaults.standard.string(forKey: lastSidebarKey) else { return nil }
        return SidebarSelectionMigration.restored(from: raw)
    }

    /// Loads the last-stable sidebar surface, or `nil` on a fresh install.
    /// `MainWindowView` falls back to `.agentChat` when this returns `nil`.
    static func loadLastSidebarSelection() -> SidebarItem? {
        storedSelection?.item
    }

    /// The panel to open on launch, for a surface that used to be its own sidebar row.
    ///
    /// Read separately from the selection so both `@State` initialisers see the same stored
    /// value without one having to depend on the other.
    static func loadRestoredPanel() -> LibraryPanel? {
        storedSelection?.panel
    }

    /// Persists only "stable" sidebar surfaces. Per-document and per-meeting selections are
    /// intentionally not persisted — those are restored via the store's `selectedDocumentID`
    /// / `selectedMeetingID`, and a deleted-document landing screen is worse than landing in
    /// chat.
    static func persistSidebarSelection(_ item: SidebarItem?) {
        guard let item,
              let raw = SidebarSelectionMigration.persistedValue(for: item)
        else { return }
        UserDefaults.standard.setValue(raw, forKey: lastSidebarKey)
    }
}
