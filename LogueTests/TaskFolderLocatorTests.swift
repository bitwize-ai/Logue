import Foundation
import Testing

@testable import Logue

/// Locating the tasks folder, against a real folder tree and a scratch defaults suite.
///
/// Every case drives `TaskFolderLocator` itself, so reverting the fix it names turns it red —
/// which is the whole reason the type exists. `TaskFolderLocator`'s header has the history.
@Suite("TaskFolderLocator")
struct TaskFolderLocatorTests {
    // MARK: - Fixtures

    /// A scratch root and defaults suite, both torn down afterwards.
    private func withScratchLibrary(
        _ body: (URL, UserDefaults) throws -> Void
    ) throws {
        let root = URL.temporaryDirectory
            .appendingPathComponent("logue-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try withScratchDefaults(label: "logue-locator") { defaults in
            try body(root.resolvingSymlinksInPath(), defaults)
        }
    }

    private func makeLocator(root: URL, defaults: UserDefaults) -> TaskFolderLocator {
        TaskFolderLocator(
            memory: TaskFolderMemory(
                defaults: defaults,
                key: AppConstants.UserDefaultsKeys.lastTaskFolderMarker
            ),
            root: { root }
        )
    }

    /// URLs built by `appendingPathComponent` carry a trailing slash and URLs from the
    /// enumerator do not, so `==` on `URL` is false for two names of the same folder.
    private func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func remembered(_ defaults: UserDefaults) -> UUID? {
        defaults.string(forKey: AppConstants.UserDefaultsKeys.lastTaskFolderMarker)
            .flatMap(UUID.init(uuidString:))
    }

    /// A marked tasks folder, as `prepare()` would leave it.
    @discardableResult
    private func makeTaskFolder(named name: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try TaskFolderStore(rootURL: folder).prepare()
        return folder
    }

    /// A space folder, which the tasks folder must never colonise.
    private func makeSpaceFolder(named name: String, in root: URL) throws {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "space".write(
            to: folder.appendingPathComponent(SpaceFile.filename),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - The retire sequence

    @Test("The folder it trashes is the folder it stops believing in")
    func forgetsTheFolderItJustTrashed() throws {
        // The ordering `retire` exists to make unspellable: forgetting first is undone by the
        // resolve on the very next line, because resolving a marked folder is itself what
        // teaches the memory.
        //
        // To falsify: in `TaskFolderLocator.retire`, replace `defer { forget() }` with a plain
        // `forget()` placed *above* `let folder = folderURL`. Hoisting the `defer` itself is a
        // no-op — Swift runs it at scope exit wherever it is registered — so that is not the
        // mutation. The straight-line version is what the code used to be, and it turns this
        // case and two others red.
        try withScratchLibrary { root, defaults in
            let folder = try makeTaskFolder(named: "Errands", in: root)
            let locator = makeLocator(root: root, defaults: defaults)

            #expect(samePath(locator.folderURL, folder), "found by its marker, not its name")
            #expect(remembered(defaults) != nil, "resolving is what teaches the memory")

            var trashed: URL?
            try locator.retire { trashed = $0; try FileManager.default.removeItem(at: $0) }

            #expect(trashed.map { samePath($0, folder) } == true)
            #expect(remembered(defaults) == nil, "the trashed folder must not stay remembered")
        }
    }

    @Test("A folder restored after being retired does not win on the old memory")
    func aRestoredFolderIsNotStillOurs() throws {
        // The user-visible consequence of getting the order wrong: they clear their data, later
        // restore that folder from the Trash for some unrelated reason, and the app hands them
        // back the library they had told it to throw away.
        try withScratchLibrary { root, defaults in
            let folder = try makeTaskFolder(named: "Errands", in: root)
            let marker = try #require(TaskFolderStore(rootURL: folder).markerIdentifier)
            let locator = makeLocator(root: root, defaults: defaults)

            _ = locator.folderURL
            #expect(remembered(defaults) == marker)

            let elsewhere = URL.temporaryDirectory
                .appendingPathComponent("logue-restore-\(UUID().uuidString)", isDirectory: true)
            try locator.retire { try FileManager.default.moveItem(at: $0, to: elsewhere) }
            defer { try? FileManager.default.removeItem(at: elsewhere) }

            // Restored by hand, exactly as it was, marker included.
            try FileManager.default.moveItem(at: elsewhere, to: folder)

            // The observation has to be a *resolve*, not another `UserDefaults` read: a read
            // alone cannot be influenced by anything on disk, so it would restate the previous
            // case rather than test the restore. What matters is that the restored folder is
            // adopted afresh — it wins on being the only marked folder — and not because the
            // app still believed in it. Its marker is unchanged, so the two are told apart by
            // the memory having been empty at the moment of the resolve.
            #expect(remembered(defaults) == nil, "the restore must not resurrect the old memory")
            #expect(samePath(locator.folderURL, folder), "adopted again, on its own merits")
            #expect(remembered(defaults) == marker, "and re-learned only by that fresh resolve")
        }
    }

    @Test("Retiring a folder that is not there still forgets it")
    func retiringAnAbsentFolderStillForgets() throws {
        // The `guard fileExists` early-exits before `trash`, so the forget has to be in a
        // `defer` rather than after the call — otherwise a user whose folder is already gone
        // keeps a marker pointing at it forever.
        try withScratchLibrary { root, defaults in
            let folder = try makeTaskFolder(named: "Errands", in: root)
            let locator = makeLocator(root: root, defaults: defaults)
            _ = locator.folderURL
            #expect(remembered(defaults) != nil)

            try FileManager.default.removeItem(at: folder)

            var trashCalled = false
            locator.retire { _ in trashCalled = true }

            #expect(trashCalled == false)
            #expect(remembered(defaults) == nil)
        }
    }

    @Test("A trash that throws still stops us believing in the folder")
    func aFailedTrashStillForgets() throws {
        // `retire` rethrows, so `clearAllData` logs and the folder survives. The forget still
        // happens, because it is in the `defer`: the user asked for that folder to be gone, and
        // the next resolve should read what is actually on disk rather than what we believed
        // before they asked.
        struct TrashFailed: Error {}

        try withScratchLibrary { root, defaults in
            try makeTaskFolder(named: "Errands", in: root)
            let locator = makeLocator(root: root, defaults: defaults)
            _ = locator.folderURL
            let before = remembered(defaults)

            #expect(throws: TrashFailed.self) {
                try locator.retire { _ in throw TrashFailed() }
            }

            // A `defer` covers the throwing exit too, which is the deliberate choice: the folder
            // survived, but the user asked for it to be gone, and the next resolve re-learns
            // whatever is actually there rather than trusting what we believed before.
            #expect(before != nil)
            #expect(remembered(defaults) == nil)
        }
    }

    // MARK: - Resolution

    @Test("A folder renamed in Finder is still found")
    func aRenamedFolderIsFoundByItsMarker() throws {
        try withScratchLibrary { root, defaults in
            let original = try makeTaskFolder(named: "Tasks", in: root)
            let locator = makeLocator(root: root, defaults: defaults)
            #expect(samePath(locator.folderURL, original))

            let renamed = root.appendingPathComponent("Errands", isDirectory: true)
            try FileManager.default.moveItem(at: original, to: renamed)
            locator.invalidate()

            #expect(samePath(locator.folderURL, renamed), "by marker; by name this reads as missing")
        }
    }

    @Test("A space already named Tasks is stepped over, not colonised")
    func anOccupiedNameIsSteppedOver() throws {
        // A real library had `~/Logue/Tasks` holding a hundred documents. Writing our marker in
        // there would put two identities on one folder, and the space is the one that loses.
        try withScratchLibrary { root, defaults in
            try makeSpaceFolder(named: "Tasks", in: root)
            let locator = makeLocator(root: root, defaults: defaults)

            #expect(locator.folderURL.lastPathComponent == "Tasks 2")
        }
    }

    @Test("A missing root returns the folder we knew, never a fresh one")
    func aMissingRootKeepsTheKnownFolder() throws {
        // An unmounted drive, a folder dragged elsewhere and a half-finished sync are
        // indistinguishable from "everything was deleted". Re-resolving here would answer
        // `<root>/Tasks`, and the next write would recreate the whole library underneath it.
        //
        // The root is really removed rather than hidden behind an injected `fileExists`. The
        // injected version did not discriminate: `resolve(in:)` reaches the filesystem through
        // `TaskFolderStore`, which never consults the closure, so with the guard deleted the
        // walk still found the folder and the case passed either way — the very failure mode
        // this suite exists to end.
        try withScratchLibrary { root, defaults in
            let folder = try makeTaskFolder(named: "Errands", in: root)
            let locator = makeLocator(root: root, defaults: defaults)
            #expect(samePath(locator.folderURL, folder))

            try FileManager.default.removeItem(at: root)

            // Delete the `guard fileExists(root)` in `resolvedFolderURL` and this answers
            // `<root>/Tasks`, because the walk finds nothing and falls through to the default.
            #expect(samePath(locator.folderURL, folder), "not <root>/Tasks")
        }
    }

    @Test("The cache is not consulted once the folder it names is gone")
    func aStaleCacheIsNotTrusted() throws {
        // The watcher debounces and `rescan` can decline to run, so between a rename in Finder
        // and the next scan the cache still names the old folder. A write in that window would
        // recreate `<root>/Tasks` and hide every file in the folder the user renamed.
        try withScratchLibrary { root, defaults in
            let original = try makeTaskFolder(named: "Tasks", in: root)
            let locator = makeLocator(root: root, defaults: defaults)
            #expect(samePath(locator.folderURL, original))

            let renamed = root.appendingPathComponent("Errands", isDirectory: true)
            try FileManager.default.moveItem(at: original, to: renamed)

            // Deliberately no `invalidate()` — this is the window where nothing has told us.
            #expect(samePath(locator.folderURL, renamed))
        }
    }
}
