import Foundation
import os.log

/// One-time relocation of user data out of the legacy App Sandbox container.
///
/// Releases up to and including 1.0.0 shipped sandboxed. Under the sandbox,
/// `URL.applicationSupportDirectory`, `NSHomeDirectory()` and `UserDefaults` all
/// resolve inside `~/Library/Containers/com.bitwize.logue/Data/…`.
///
/// The sandbox was removed so Logue can act as an Accessibility API client — macOS
/// refuses to list a sandboxed app in Privacy & Security → Accessibility at all
/// (https://github.com/bitwize-ai/Logue/issues/22). That flip re-points every one of
/// those lookups at the real home directory, which would orphan an upgrading user's
/// meetings, documents, spaces, vector store and several GB of downloaded models.
///
/// This runs once, as early as possible in `LogueApp.init()` — before any store
/// singleton resolves its directory — and moves the container's contents to their
/// unsandboxed equivalents.
enum SandboxContainerMigrator {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "SandboxMigration")

    /// Paths to relocate. The container mirrors the home directory layout, so the
    /// same relative path describes both the source and the destination.
    private static let relativePaths = [
        "Library/Application Support/Logue", // meetings, documents, templates, spaces, scheduled tasks
        "Library/Application Support/\(AppConstants.bundleID)", // vector store + meeting memory index
        "Library/Application Support/FluidAudio", // diarization models (~700 MB)
        "Library/Application Support/LocalLLM", // MLX models, when stored under Application Support
        ".localllmclient", // MLX model store (~2 GB)
        ".cache/huggingface", // Hugging Face download cache
    ]

    // MARK: - Entry Point

    /// Moves legacy container data into place if this is the first unsandboxed launch.
    ///
    /// Safe to call unconditionally: it no-ops once the migration has run, when no
    /// container exists (clean install), and when still running sandboxed.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppConstants.UserDefaultsKeys.sandboxContainerMigrationCompleted) else { return }

        guard let container = legacyContainerDataDirectory else {
            // Nothing to migrate — record it so we stop looking on every launch.
            defaults.set(true, forKey: AppConstants.UserDefaultsKeys.sandboxContainerMigrationCompleted)
            return
        }

        logger.info("Legacy sandbox container found — migrating user data out of it")
        migratePreferences(from: container)
        for relativePath in relativePaths {
            migrateItem(relativePath, from: container)
        }

        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.sandboxContainerMigrationCompleted)
        logger.info("Sandbox container migration complete")
    }

    // MARK: - Location

    /// The legacy container's `Data` directory, or `nil` when there is nothing to migrate.
    private static var legacyContainerDataDirectory: URL? {
        // Inside a sandbox `NSHomeDirectory()` *is* the container, so the migration is
        // both meaningless and destructive. Bail out.
        guard !isSandboxed else { return nil }

        let container = url(
            realHomeDirectory,
            "Library/Containers/\(AppConstants.bundleID)/Data"
        )
        return FileManager.default.fileExists(atPath: container.path) ? container : nil
    }

    private static var realHomeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `APP_SANDBOX_CONTAINER_ID` is injected into the environment of every sandboxed
    /// process, so its presence is a reliable runtime sandbox check.
    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Appends a `/`-separated relative path one component at a time so directory
    /// names containing spaces ("Application Support") are handled correctly.
    private static func url(_ base: URL, _ relativePath: String) -> URL {
        relativePath
            .split(separator: "/")
            .reduce(base) { $0.appendingPathComponent(String($1)) }
    }

    // MARK: - Files

    private static func migrateItem(_ relativePath: String, from container: URL) {
        let source = url(container, relativePath)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        move(source, to: url(realHomeDirectory, relativePath), label: relativePath)
    }

    /// Moves `source` onto `destination`, merging directories that already exist.
    ///
    /// Never overwrites: anything already present at the destination wins and the
    /// container copy is left in place and logged, so a machine that ran both a
    /// sandboxed release and a local Debug build cannot lose either side.
    ///
    /// Merging rather than skipping the whole tree matters for shared locations like
    /// `~/.cache/huggingface`, which already exists on any machine that has touched
    /// Hugging Face tooling — skipping it wholesale would strand gigabytes of models
    /// in the container and force a re-download.
    /// Internal rather than private so `SandboxContainerMigratorTests` can exercise the
    /// merge and non-clobber rules against a scratch directory. Call only from
    /// `migrateItem` and its own recursion.
    static func move(_ source: URL, to destination: URL, label: String) {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: destination.path) else {
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                // Container and home are on the same volume, so this is a rename:
                // instant, and it needs no extra free space — which matters for the
                // multi-GB model directories.
                try fileManager.moveItem(at: source, to: destination)
                logger.info("Migrated \(label, privacy: .public) out of the sandbox container")
            } catch {
                logger.error(
                    "Failed to migrate \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            return
        }

        guard isDirectory(source), isDirectory(destination) else {
            logger.notice("Left \(label, privacy: .public) in the container — destination already exists")
            return
        }

        // Both sides are directories: recurse so non-colliding children still migrate.
        let children: [String]
        do {
            children = try fileManager.contentsOfDirectory(atPath: source.path)
        } catch {
            logger.error(
                "Failed to enumerate \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        for child in children {
            move(
                source.appendingPathComponent(child),
                to: destination.appendingPathComponent(child),
                label: "\(label)/\(child)"
            )
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Stale Absolute Paths

    /// The path segment the sandbox inserted in front of every absolute path.
    static var containerPathSegment: String {
        "/Library/Containers/\(AppConstants.bundleID)/Data"
    }

    /// Rewrites an absolute file URL captured while sandboxed so it points at the
    /// migrated location.
    ///
    /// `MeetingNote.audioFileURL` is the only absolute path Logue persists. It is
    /// recorded when a recording finishes and stored verbatim, so meetings captured by
    /// a sandboxed build (≤ 1.0.0) still reference
    /// `…/Library/Containers/com.bitwize.logue/Data/Library/Application Support/…`
    /// after `migrateIfNeeded()` has moved the file out to the real home directory.
    /// Without this rewrite `AudioPlaybackView` renders a player for a file that is no
    /// longer at that path and playback silently does nothing.
    ///
    /// Returns the original URL when nothing exists at the rewritten path — the file is
    /// still in the container whenever a migration step was skipped as a non-clobber.
    static func resolvingLegacyContainerPath(_ url: URL?) -> URL? {
        guard let url, url.isFileURL else { return url }

        let path = url.path(percentEncoded: false)
        guard let segment = path.range(of: containerPathSegment) else { return url }

        let rewritten = path.replacingCharacters(in: segment, with: "")
        guard FileManager.default.fileExists(atPath: rewritten) else { return url }
        return URL(fileURLWithPath: rewritten)
    }

    // MARK: - Preferences

    /// Copies the container's preference domain into the real one, without overwriting
    /// anything the unsandboxed domain has already set.
    private static func migratePreferences(from container: URL) {
        let plist = url(container, "Library/Preferences/\(AppConstants.bundleID).plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { return }

        guard let legacy = readPreferences(at: plist) else { return }

        let defaults = UserDefaults.standard
        var migrated = 0
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            // System-managed domains rebuild themselves; carrying them over can
            // resurrect stale sandbox-era state.
            guard !key.hasPrefix("com.apple.") else { continue }
            defaults.set(value, forKey: key)
            migrated += 1
        }
        logger.info("Migrated \(migrated) preference key(s) out of the sandbox container")
    }

    private static func readPreferences(at plist: URL) -> [String: Any]? {
        do {
            let data = try Data(contentsOf: plist)
            let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let dictionary = parsed as? [String: Any] else {
                logger.error("Legacy preferences plist was not a dictionary — skipping")
                return nil
            }
            return dictionary
        } catch {
            logger.error("Failed to read legacy preferences: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
