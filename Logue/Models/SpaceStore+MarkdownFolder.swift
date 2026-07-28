import Foundation
import OSLog

/// Keeping folders in step with spaces changed inside the app.
///
/// Without this half, the two sides fight. A space renamed in the app left its folder under the
/// old name, so the next scan read the folder as the truth and renamed the space back. A space
/// deleted in the app left its folder behind, and the `_space.md` inside it still named the
/// space — so the next scan created it again. And a scan cannot tell those apart from the user
/// renaming or deleting the folder themselves; both look like a name that does not match.
///
/// So the rule is: **a structural change made in the app is written to disk immediately.** That
/// is what earns the scan the right to read a missing folder as a deletion rather than guessing.
@MainActor
extension SpaceStore {
    private static let folderLogger = Logger(
        subsystem: AppConstants.bundleID, category: "SpaceFolders"
    )

    private var storage: DocumentStorage {
        DocumentStorage.shared
    }

    /// Creates the folder for a newly made space.
    func createFolder(for space: Space) {
        guard storage.mode.isMarkdown else { return }
        do {
            try storage.liveMigrator.createFolder(for: space, in: spaces)
        } catch {
            Self.folderLogger.error(
                "Could not create a folder for a new space: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Moves the folder of a space that was renamed or re-parented.
    ///
    /// `previousComponents` has to be captured **before** the space changes: they are derived from
    /// the name and parent chain, so afterwards the old path is unrecoverable.
    func moveFolder(for spaceID: UUID, from previousComponents: [String]) {
        guard storage.mode.isMarkdown,
              let space = spaces.first(where: { $0.id == spaceID })
        else { return }

        do {
            try storage.liveMigrator.moveFolder(from: previousComponents, for: space, in: spaces)
        } catch {
            // The folder keeps its old name. The next scan then reads that name as the truth and
            // renames the space back — visible and reversible, unlike silently diverging.
            Self.folderLogger.error(
                "Could not move a space folder: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Moves the folders of deleted spaces to the Trash.
    ///
    /// Takes paths rather than identifiers because by the time this is useful the spaces are gone
    /// from the store and their paths can no longer be derived.
    func retireFolders(at paths: [[String]]) {
        guard storage.mode.isMarkdown else { return }
        let migrator = storage.liveMigrator

        for components in paths {
            do {
                try migrator.retireFolder(at: components)
            } catch {
                Self.folderLogger.error(
                    "Could not move a space folder to the Trash: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// The folder path a space currently occupies, for capturing before a change.
    func folderComponents(for spaceID: UUID) -> [String] {
        MirrorLayout.directoryComponents(forSpace: spaceID, in: spaces)
    }

    /// Rewrites a space's `_space.md`, for a change to its icon or colour.
    func refreshFolderIdentity(for spaceID: UUID) {
        guard storage.mode.isMarkdown,
              let space = spaces.first(where: { $0.id == spaceID })
        else { return }
        storage.liveMigrator.writeSpaceIdentities(spaces: [space], among: spaces)
    }
}
