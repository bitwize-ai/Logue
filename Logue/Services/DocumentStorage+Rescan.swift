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

    /// Starts watching the folder, if markdown storage is on and it is not already running.
    ///
    /// Safe to call repeatedly, and called on every scan, because starting can fail: the folder may
    /// be on a drive that is not mounted yet, or the user may have moved it. Guarding on "have we
    /// made a watcher" instead of "is one running" meant a single failure at launch cost the whole
    /// session's live updates, silently.
    func startWatchingIfNeeded() {
        guard mode.isMarkdown else { return }
        if let watcher, watcher.isRunning {
            return
        }

        let created = watcher ?? MarkdownFolderWatcher(url: Self.markdownRootURL) {
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
    /// `announcing` is false for scans the user did not ask for — coming back to the app, say. They
    /// do the same work and report the same summary, but they leave the button alone, because a
    /// spinner on every window focus is noise rather than information.
    @discardableResult
    func rescan(
        minimumVisibleDuration: Duration? = AppConstants.Delays.rescanMinimumVisible,
        announcing: Bool = true
    ) async -> ExternalChangePlan? {
        guard mode.isMarkdown else { return nil }

        // A scan arriving while one is running is remembered rather than dropped. Two at once would
        // fight over the same files, but discarding the second lost the change that prompted it —
        // and the window is wide, because the indicator is deliberately held for a moment.
        if isScanInFlight {
            hasPendingScan = true
            return nil
        }

        // Cheap when it is already running, and the only thing that recovers a watcher that could
        // not start earlier.
        startWatchingIfNeeded()

        isScanInFlight = true
        if announcing {
            beginScan()
        }
        invalidateFileIndex()
        let started = ContinuousClock.now

        let spaceStore = SpaceStore.shared
        let documentStore = DocumentStore.shared
        let scan = MarkdownFolderScan(rootURL: Self.markdownRootURL)

        // Nothing at all if the folder itself is missing. See `isRootPresent`: a moved folder or
        // an unfinished sync is indistinguishable from a deleted one, and acting on it would
        // empty the library.
        guard scan.isRootPresent else {
            Self.scanLogger.error("Skipped a scan: the documents folder is not there")
            finishScan(summary: nil, announcing: announcing)
            return nil
        }

        // What the library held before the walk began — the contents, not only the identifiers.
        //
        // Everything downstream that asks "did this move on during the scan?" has to ask it against
        // *this*, because the walk is the long wait and it is where the user types. Reading the
        // baseline afterwards made the question almost meaningless: it only ever caught mutations
        // landing during the short plan step, so an edit made while the folder was being read was
        // compared against itself, looked settled, and the file's older text was written over it.
        let baseline = documentStore.documents.map(\.content)

        // One traversal, read off the main actor, handed to every step below. Each of those steps
        // used to start its own — seven per scan, three of them opening every document in the
        // library, and all of it on the main actor on every app activation.
        let snapshot = await Task.detached { scan.snapshot() }.value

        // Deletions before adoption, or a space whose folder is gone would be handed straight back
        // to `adoptNewFolders` as a folder to recreate.
        deleteVanishedSpaces(using: scan, spaceStore: spaceStore, snapshot: snapshot)

        // Renames before creations: a folder that moved is the same space, and reading it as a new
        // one would leave the old space behind with no folder — which the next scan deletes.
        applyFolderRenames(using: scan, spaceStore: spaceStore, snapshot: snapshot)

        // Folders next, and on the main actor because it mutates the space store: the
        // spaces have to exist before a document can be filed into one.
        adoptNewFolders(using: scan, spaceStore: spaceStore, snapshot: snapshot)

        let spaces = spaceStore.spaces
        let known = documentStore.documents.map(\.content)
        // The index the cross-check needs: where each document's file was last seen, so absence from
        // the walk can be tested against the filesystem rather than believed. From the snapshot, so
        // it costs nothing extra.
        let lastKnownFiles = liveMigrator.fileIndex(using: snapshot)
        let plan = await buildPlan(
            scan, spaces: spaces, known: known, lastKnownFiles: lastKnownFiles, snapshot: snapshot
        )

        report(
            plan,
            duplicatedFolders: scan.duplicatedSpaceFolders(in: spaceStore.spaces, using: snapshot)
        )

        // Compared against the pre-walk baseline, not `known`. `known` is read after the walk, so
        // using it asked whether anything changed during the *plan* — a few milliseconds — rather
        // than during the read, which is the whole window. Three ordinary things happening while
        // the folder is read went wrong that way: an edit was overwritten with the file's older
        // text, a restore was undone and its file binned, and a document dragged to another space
        // jumped back.
        //
        // `known` still feeds the plan itself. It has to: `deleteVanishedSpaces` above legitimately
        // trashes documents, and diffing against a baseline that predates that would resurrect them.
        let current = documentStore.documents.map(\.content)
        var settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: baseline, current: current
        )
        keepDeletionsThatMovedOn(in: &settled, baseline: baseline, current: current)

        if settled.updated.count != plan.updated.count {
            Self.scanLogger.info(
                "Held back \(plan.updated.count - settled.updated.count, privacy: .public) update(s) for a document edited during the scan"
            )
            // Queued rather than only logged. `kFSEventStreamCreateFlagIgnoreSelf` means our own next
            // write produces no event, so a held-back external edit had nothing left to trigger it and
            // sat unapplied until the app happened to overwrite the file.
            hasPendingScan = true
        }

        documentStore.applyExternalChanges(settled)
        retryUnwritableDocuments(in: documentStore)

        if let minimumVisibleDuration {
            let remaining = minimumVisibleDuration - started.duration(to: .now)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
        }

        finishScan(summary: settled.summary, announcing: announcing)

        // Whatever arrived mid-scan gets its own pass now, once, however many times it was asked for.
        if hasPendingScan {
            hasPendingScan = false
            return await rescan(minimumVisibleDuration: nil, announcing: announcing)
        }

        return settled
    }

    /// Everything a scan found that the user cannot see for themselves.
    ///
    /// Logged rather than surfaced: each of these is a folder or file in an odd state that the app is
    /// deliberately leaving alone, and none of them needs an interruption.
    private func report(_ plan: ExternalChangePlan, duplicatedFolders: [[String]]) {
        for folder in duplicatedFolders {
            Self.scanLogger.info(
                "Two folders claim the same space; keeping the one the space is named after, ignoring \(folder.count, privacy: .public) level(s) deep"
            )
        }

        if !plan.unwalkable.isEmpty {
            Self.scanLogger.error(
                "\(plan.unwalkable.count, privacy: .public) document(s) were not returned by the walk but their files are still there; left alone"
            )
        }

        if !plan.ambiguousIdentifiers.isEmpty {
            Self.scanLogger.info(
                "\(plan.ambiguousIdentifiers.count, privacy: .public) document(s) have more than one file and were left untouched"
            )
        }

        if !plan.ignoredIdentifiers.isEmpty {
            Self.scanLogger.info(
                "\(plan.ignoredIdentifiers.count, privacy: .public) file(s) name a document that does not exist and were left alone"
            )
        }
    }

    private func finishScan(summary: String?, announcing: Bool) {
        isScanInFlight = false
        if announcing {
            endScan(summary: summary)
        } else {
            recordScanSummary(summary)
        }
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
    private func deleteVanishedSpaces(
        using scan: MarkdownFolderScan,
        spaceStore: SpaceStore,
        snapshot: FolderSnapshot
    ) {
        let vanished = scan.vanishedSpaceIDs(in: spaceStore.spaces, using: snapshot)
        guard !vanished.isEmpty else { return }

        // Top of each deleted subtree only — `deleteSpace` cascades, and asking it to delete a
        // child after its parent is gone would find nothing.
        let roots = vanished.filter { id in
            guard let parentID = spaceStore.spaces.first(where: { $0.id == id })?.parentID
            else { return true }
            return !vanished.contains(parentID)
        }

        for id in roots {
            // The folder is already gone — that is why we are here. Retiring would recompute the path
            // from the space's name and trash whatever is at it, and deleting a folder then making a
            // new one with the same name is a normal thing to do.
            spaceStore.deleteSpace(id: id, retiringFolder: false)
        }
        Self.scanLogger.info(
            "Removed \(vanished.count, privacy: .public) space(s) whose folder was deleted"
        )
    }

    /// Follows folders that were renamed or moved in Finder.
    private func applyFolderRenames(
        using scan: MarkdownFolderScan,
        spaceStore: SpaceStore,
        snapshot: FolderSnapshot
    ) {
        let renames = scan.folderRenames(in: spaceStore.spaces, using: snapshot)
        guard !renames.isEmpty else { return }

        for rename in renames {
            spaceStore.adoptSpaceRename(
                id: rename.id,
                name: rename.name,
                parentID: SpaceFolderLayout.spaceID(
                    forDirectoryComponents: rename.parentComponents, in: spaceStore.spaces
                )
            )
        }
        Self.scanLogger.info("Followed \(renames.count, privacy: .public) folder rename(s)")
    }

    /// Turns folders created outside the app into spaces.
    ///
    /// A folder that already has a space must produce nothing here. The check runs through
    /// `SpaceFolderLayout` — the same code that decides where a space writes its folder — so the
    /// two cannot disagree and invent a space on every pass.
    private func adoptNewFolders(
        using scan: MarkdownFolderScan,
        spaceStore: SpaceStore,
        snapshot: FolderSnapshot
    ) {
        let creations = scan.spaceCreations(in: spaceStore.spaces, using: snapshot)
        guard !creations.isEmpty else { return }

        for creation in creations {
            // A folder that already claims an existing space is not a creation — `folderRenames`
            // handled it. What reaches here claims nothing, or claims a space that no longer
            // exists: a folder restored from a backup, which keeps the identity it had.
            let identity = scan.identity(
                forDirectoryComponents: creation.components, using: snapshot
            )
            let adopted = spaceStore.adoptSpace(
                id: identity?.id ?? UUID(),
                name: creation.name,
                parentID: SpaceFolderLayout.spaceID(
                    forDirectoryComponents: creation.parentComponents, in: spaceStore.spaces
                ),
                icon: identity?.icon,
                color: identity?.color,
                sortOrder: identity?.sortOrder
            )

            // Written at the folder's *known* path rather than one derived from the name. A folder
            // called `-Work` gives a space called `-Work`, whose derived path is `Work` — a folder
            // that does not exist. The identity therefore never got written, and the next scan read
            // the space as having no folder and deleted it.
            if let adopted {
                scan.writeSpaceIdentity(for: adopted, atComponents: creation.components)
            }
        }
        Self.scanLogger.info("Adopted \(creations.count, privacy: .public) folder(s) as spaces")
    }

    /// Diffs the folder against the library, off the main actor.
    ///
    /// `unwritableDocuments` is read here rather than inside the detached task: it is main-actor
    /// state, and it says which documents have no file because writing one failed. Their absence
    /// from the walk is our own doing, not the user deleting anything.
    private func buildPlan(
        _ scan: MarkdownFolderScan,
        spaces: [Space],
        known: [DocumentContent],
        lastKnownFiles: [UUID: URL],
        snapshot: FolderSnapshot
    ) async -> ExternalChangePlan {
        let withoutFiles = unwritableDocuments
        return await Task.detached {
            scan.plan(
                spaces: spaces,
                known: known,
                lastKnownFiles: lastKnownFiles,
                withoutFiles: withoutFiles,
                using: snapshot
            )
        }.value
    }

    /// Re-attempts the write for every document recorded as having no file.
    ///
    /// Nothing else did. An id entered that set on a failed export and left it only on a *later*
    /// successful save, so a document edited while the folder's drive was unmounted was written to
    /// encrypted storage and then never touched again — invisible to anything syncing `~/Logue`,
    /// permanently exempt from the deletion check, and reported only as a log line. A scan is the
    /// natural retry point: it already runs when the folder becomes reachable again, and a
    /// successful `save` clears the record itself.
    ///
    /// Ids the store no longer holds are dropped rather than retried — a document permanently
    /// deleted since the failure has nothing left to write.
    private func retryUnwritableDocuments(in documentStore: DocumentStore) {
        guard !unwritableDocuments.isEmpty else { return }

        let byID = Dictionary(
            documentStore.documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let stale = unwritableDocuments.filter { byID[$0] == nil }
        clearUnwritable(stale)

        let spaces = SpaceStore.shared.spaces
        var recovered = 0
        var failed = 0
        for id in unwritableDocuments {
            guard let document = byID[id], !document.isTrashed else { continue }
            if save(document, spaces: spaces) {
                recovered += 1
            } else {
                failed += 1
            }
        }
        // A failed export invalidates both folder caches, so without this the next iteration paid
        // a full traversal that opens every `.md` in the library — on the main actor, once per
        // still-failing document, on every scan. That is a stall scaling with the number of
        // unwritable documents times the library size, for exactly the user whose disk is full.
        if failed > 0 {
            invalidateFileIndex()
        }
        if recovered > 0 {
            Self.scanLogger.info(
                "Wrote \(recovered, privacy: .public) document(s) that had failed to reach the folder"
            )
        }
    }

    /// Applies `ExternalChangePlanner.keepingDeletionsThatMovedOn` and reports what it saved.
    ///
    /// The rule itself lives next to `discardingUpdatesThatMovedOn`, where it is pure and tested;
    /// what stays here is the part that needs the store — logging, and asking for another scan so
    /// the rescued documents get diffed against a walk that could have seen them.
    private func keepDeletionsThatMovedOn(
        in plan: inout ExternalChangePlan, baseline: [DocumentContent], current: [DocumentContent]
    ) {
        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: baseline, current: current
        )
        guard !kept.isEmpty else { return }

        plan = settled
        Self.scanLogger.info(
            "Kept \(kept.count, privacy: .public) document(s) whose file appeared during the scan"
        )
        hasPendingScan = true
    }
}
