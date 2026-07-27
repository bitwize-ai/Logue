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
                DocumentStorage.shared.rescan()
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
    @discardableResult
    func rescan() -> ExternalChangePlan? {
        guard mode.isMarkdown else { return nil }

        setScanState(true)
        defer { setScanState(false) }

        let spaceStore = SpaceStore.shared
        let documentStore = DocumentStore.shared
        let scan = MarkdownFolderScan(rootURL: Self.markdownRootURL, echoFilter: echoFilter)

        adoptNewFolders(using: scan, spaceStore: spaceStore)

        let plan = scan.plan(
            spaces: spaceStore.spaces, known: documentStore.documents.map(\.content)
        )

        if !plan.ignoredIdentifiers.isEmpty {
            Self.scanLogger.info(
                "\(plan.ignoredIdentifiers.count, privacy: .public) file(s) name a document that does not exist and were left alone"
            )
        }

        documentStore.applyExternalChanges(plan)
        setScanState(true, summary: plan.summary)
        return plan
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
