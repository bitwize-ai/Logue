import Foundation

/// Where the tasks folder is, and when to stop believing in it.
///
/// Takes its root and its memory rather than reading `DocumentStorage.markdownRootURL` and
/// `UserDefaults.standard`, for the same reason `TaskFolderStore` takes its root as a parameter:
/// a rule nothing can execute is a rule that gets rewritten wrong. Four consecutive rounds of
/// review found a defect in this logic while it was a set of statics over those two globals, and
/// each fix was written into a place no test could reach — so the next round found the next one.
///
/// Everything stateful about locating the folder lives here: the path cache, the marker memory,
/// and the retire sequence whose *order* is the thing that keeps being got wrong.
///
/// `@unchecked Sendable`: every mutable member is `cachedFolderURL`, and every read and write of
/// it happens with `lock` held. `memory` is a value type over `UserDefaults`, which is itself
/// thread-safe, and `root` and `fileExists` are set once in `init` and never reassigned. Tasks
/// are read and written from both the main actor and the file-watcher's queue, which is why this
/// is a lock rather than actor isolation.
final class TaskFolderLocator: @unchecked Sendable {
    private let memory: TaskFolderMemory
    private let root: () -> URL
    private let fileExists: (URL) -> Bool

    private let lock = NSLock()
    /// The last resolved location, guarded by `lock`.
    ///
    /// Remembered because resolving reads the filesystem and this is asked on every task load,
    /// save and delete: with the root pointed at a synced vault, ticking one checkbox meant
    /// walking the library before writing a byte.
    ///
    /// The risk this trades against is real and was the reason it was not cached before — a
    /// stale path is how a folder stops being found at all — so it is dropped whenever the
    /// answer can change: the storage mode switching, a scan reconciling the folder with what is
    /// on disk, and the remembered folder no longer being there. A rename made in Finder is
    /// caught by the last of those on the very next access, rather than waiting for a scan that
    /// debounces and can fail to start at all.
    ///
    /// The markdown root going missing is the one case that *keeps* it rather than dropping it,
    /// for the reason spelled out at the guard below.
    private var cachedFolderURL: URL?

    init(
        memory: TaskFolderMemory = TaskFolderMemory(),
        root: @escaping () -> URL,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.memory = memory
        self.root = root
        self.fileExists = fileExists
    }

    /// Forgets where the tasks folder is, without forgetting *which* folder is ours.
    ///
    /// Called from `DocumentStorage.invalidateFileIndex` and from the mode setter, so it drops
    /// on everything that can move the folder: a scan, a space folder created, renamed or
    /// retired, and a switch between storage modes. A rename made in Finder arrives through the
    /// scan, which is how the app learns about every other external change too.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedFolderURL = nil
    }

    var folderURL: URL {
        lock.lock()
        defer { lock.unlock() }
        return locked_folderURL()
    }

    /// Sends the tasks folder to the Trash and stops believing in it — in that order.
    ///
    /// One method rather than two calls at a call site, because the order is the whole finding.
    /// Resolving the folder in order to trash it is itself an act that teaches the memory, so a
    /// forget written before the resolve is undone by the very next line — and that is what
    /// three separate call sites did. Here the sequence cannot be spelled wrong, and
    /// `TaskFolderLocatorTests.forgetsTheFolderItJustTrashed` fails the moment it is.
    ///
    /// `trash` is passed in rather than called directly so the sequence can be driven without
    /// a Trash: it receives the resolved folder and is invoked only when that folder exists.
    func retire(_ trash: (URL) throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }

        let folder = locked_folderURL()
        defer {
            memory.forget()
            cachedFolderURL = nil
        }
        guard fileExists(folder) else { return }
        try trash(folder)
    }

    /// Stops believing in the remembered folder, for a caller that has already disposed of it.
    ///
    /// Prefer `retire(_:)`, which cannot be ordered wrongly. This exists for the two markdown
    /// paths that retire the whole root — the tasks folder goes with it, but they are not the
    /// ones doing it — and it is correct there only because the root is already gone by the
    /// time they call.
    func forget() {
        lock.lock()
        defer { lock.unlock() }
        memory.forget()
        cachedFolderURL = nil
    }

    // MARK: - Resolution

    /// - Precondition: `lock` is held.
    private func locked_folderURL() -> URL {
        // A remembered path is only trusted while it is still there. Invalidation on a scan is
        // not enough on its own: the watcher debounces, `rescan` returns early when one is
        // already in flight, and it can fail to start at all — so between a rename made in
        // Finder and the next scan the cache still names the old folder. A write in that window
        // recreates `<root>/Tasks`, which then hides every file in the folder the user actually
        // renamed. One `fileExists` on a path we already hold is cheap; the walk it guards
        // is not.
        if let cachedFolderURL, fileExists(cachedFolderURL) {
            return cachedFolderURL
        }

        // A missing root is not a moved folder. An unmounted drive, a folder dragged elsewhere
        // and a sync that has not finished all look identical to "everything was deleted", and
        // the document side refuses to act on that at all — `MarkdownFolderScan.isRootPresent`,
        // and the rule in CLAUDE.md. Re-resolving here would answer `<root>/Tasks`, and the next
        // write would recreate the whole root underneath it. The remembered path is kept until
        // the root is back, so the folder is found again rather than replaced.
        let root = root()
        guard fileExists(root) else {
            return cachedFolderURL ?? root.appendingPathComponent(
                TaskFile.folderName, isDirectory: true
            )
        }

        let resolved = resolve(in: root)
        cachedFolderURL = resolved
        return resolved
    }

    /// Where tasks live, avoiding a folder that is already a space.
    ///
    /// `Tasks` is an obvious name for a space and users really do have one — a real library
    /// turned out to have `~/Logue/Tasks` holding a hundred documents. Writing our marker in
    /// there would put two identities on one folder, and the loser would be the space, taking
    /// its documents with it. So an occupied name is stepped over rather than shared.
    private func resolve(in root: URL) -> URL {
        // Identity first. The name is only ever the *creation-time* default: once the folder
        // exists it is found by the marker it carries, so renaming it in Finder — which the
        // marker file explicitly invites — keeps tasks working instead of emptying the list.
        if let marked = TaskFolderStore.markedFolder(in: root, remembering: memory.remembered) {
            memory.rememberIfUnknown(TaskFolderStore(rootURL: marked).markerIdentifier)
            return marked
        }

        let preferred = root.appendingPathComponent(TaskFile.folderName, isDirectory: true)
        guard TaskFolderStore(rootURL: preferred).isExistingSpaceFolder else { return preferred }

        for suffix in 2 ... 20 {
            let candidate = root.appendingPathComponent(
                "\(TaskFile.folderName) \(suffix)", isDirectory: true
            )
            if !TaskFolderStore(rootURL: candidate).isExistingSpaceFolder {
                return candidate
            }
        }
        // Twenty spaces all named some variant of "Tasks" is not a real library; take the
        // preferred name back and let `prepare()` refuse it loudly.
        return preferred
    }
}
