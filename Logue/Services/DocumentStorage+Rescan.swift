import Foundation
import OSLog

/// Reading the folder back: watching it, and applying what changed.
///
/// The rule the whole extension is built around: **in markdown mode the file is the
/// document.** A scan therefore updates the app and writes nothing back, so no scan can
/// overwrite a file, and no write can be mistaken for an edit. The one write a scan does make
/// is stamping an identifier into a file that was dropped in, which is what stops the same
/// file being adopted over and over.
@MainActor
extension DocumentStorage {
    private static let scanLogger = Logger(subsystem: AppConstants.bundleID, category: "DocumentFolderScan")

    // MARK: - Watching

    /// Starts watching the folder, if markdown storage is on.
    func startWatchingIfNeeded() {
        guard mode.isMarkdown, watcher == nil else { return }

        let created = MarkdownFolderWatcher(url: Self.markdownRootURL) {
            // The watcher fires on its own queue; everything a scan touches is main-actor
            // state.
            Task { @MainActor in
                await DocumentStorage.shared.rescan()
            }
        }
        watcher = created
        created.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        echoFilter.reset()
    }

    // MARK: - Scanning

    /// Reads the folder and applies whatever changed, returning what it found.
    ///
    /// Safe to call at any time — from the watcher, from the rescan button, or on launch. A
    /// scan that finds nothing does nothing at all, which is what keeps the watcher from
    /// turning our own saves into work.
    ///
    /// Reading is done off the main actor. That is not only about a folder large enough to
    /// stall a keystroke: it is also what makes `isScanning` observable at all. A synchronous
    /// scan sets the flag and clears it within one main-actor call, so SwiftUI never draws a
    /// frame in between and no progress indicator could ever appear.
    ///
    /// `minimumVisibleDuration` holds the indicator on screen when the scan is faster than
    /// the eye — which it usually is. It applies to background scans too, and costs them
    /// nothing: the wait happens after the changes have already been applied, and without it
    /// a watcher-driven scan would make the button flicker for a frame or two.
    @discardableResult
    func rescan(
        minimumVisibleDuration: Duration? = AppConstants.Delays.rescanMinimumVisible
    ) async -> ExternalChangePlan? {
        guard mode.isMarkdown else { return nil }
        // A second press while one is running would fight the first over the same files.
        guard !isScanning else { return nil }

        beginScan()
        let started = ContinuousClock.now

        let spaceStore = SpaceStore.shared
        let documentStore = DocumentStore.shared
        let scan = MarkdownFolderScan(rootURL: Self.markdownRootURL, echoFilter: echoFilter)

        // Nothing at all if the folder itself is missing. See `isRootPresent`: a moved folder or
        // an unfinished sync is indistinguishable from a deleted one, and acting on it would
        // empty the library.
        guard scan.isRootPresent else {
            Self.scanLogger.error("Skipped a scan: the documents folder is not there")
            endScan(summary: nil)
            return nil
        }

        // Deletions before adoption, or a space whose folder is gone would be handed straight back
        // to `adoptNewFolders` as a folder to recreate.
        deleteVanishedSpaces(using: scan, spaceStore: spaceStore)

        // Folders next, and on the main actor because it mutates the space store: the
        // spaces have to exist before a document can be filed into one.
        adoptNewFolders(using: scan, spaceStore: spaceStore)

        let spaces = spaceStore.spaces
        let known = documentStore.documents.map(\.content)
        let plan = await Task.detached { scan.plan(spaces: spaces, known: known) }.value

        if !plan.ignoredIdentifiers.isEmpty {
            Self.scanLogger.info(
                "\(plan.ignoredIdentifiers.count, privacy: .public) file(s) name a document that does not exist and were left alone"
            )
        }

        documentStore.applyExternalChanges(plan)

        if let minimumVisibleDuration {
            let remaining = minimumVisibleDuration - started.duration(to: .now)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
        }

        endScan(summary: plan.summary)
        return plan
    }

    /// Removes spaces whose folder the user deleted.
    ///
    /// `deleteSpace` does the rest of the work: it takes nested spaces with it and trashes the
    /// documents and meetings inside them. The documents' files are already gone with the folder,
    /// so the document scan that follows finds nothing left to do for them.
    ///
    /// Deleting a folder is a real instruction, but a whole tree of notes is a lot to lose to a
    /// misread, so nothing here destroys anything: the documents go to Logue's trash and the
    /// folder is already in the user's.
    private func deleteVanishedSpaces(using scan: MarkdownFolderScan, spaceStore: SpaceStore) {
        let vanished = scan.vanishedSpaceIDs(in: spaceStore.spaces)
        guard !vanished.isEmpty else { return }

        // Top of each deleted subtree only — `deleteSpace` cascades, and asking it to delete a
        // child after its parent is gone would find nothing.
        let roots = vanished.filter { id in
            guard let parentID = spaceStore.spaces.first(where: { $0.id == id })?.parentID
            else { return true }
            return !vanished.contains(parentID)
        }

        for id in roots {
            spaceStore.deleteSpace(id: id)
        }
        Self.scanLogger.info(
            "Removed \(vanished.count, privacy: .public) space(s) whose folder was deleted"
        )
    }

    /// Turns folders created outside the app into spaces.
    ///
    /// A folder that already has a space must produce nothing here. The check runs through
    /// `MirrorLayout` — the same code that decides where a space writes its folder — so the
    /// two cannot disagree and invent a space on every pass.
    private func adoptNewFolders(using scan: MarkdownFolderScan, spaceStore: SpaceStore) {
        let creations = scan.spaceCreations(in: spaceStore.spaces)
        guard !creations.isEmpty else { return }

        for creation in creations {
            let identity = scan.identity(forDirectoryComponents: creation.components)
            let resolution = SpaceFolderAdoption.resolve(
                creation, claimedID: identity?.id, in: spaceStore.spaces
            )

            switch resolution {
            case let .rename(id, name, parentComponents):
                spaceStore.adoptSpaceRename(
                    id: id,
                    name: name,
                    parentID: MirrorLayout.spaceID(
                        forDirectoryComponents: parentComponents, in: spaceStore.spaces
                    )
                )
            case let .create(id, name, parentComponents):
                spaceStore.adoptSpace(
                    id: id ?? UUID(),
                    name: name,
                    parentID: MirrorLayout.spaceID(
                        forDirectoryComponents: parentComponents, in: spaceStore.spaces
                    ),
                    icon: identity?.icon,
                    color: identity?.color
                )
            }
        }

        // Give the new folders their `_space.md`, so renaming one later reads as a rename
        // rather than as a delete plus a create.
        scan.writeSpaceIdentities(spaces: spaceStore.spaces)
        Self.scanLogger.info("Adopted \(creations.count, privacy: .public) folder(s) as spaces")
    }
}
