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
        let fileManager = FileManager.default
        let source = url(container, relativePath)
        guard fileManager.fileExists(atPath: source.path) else { return }

        let destination = url(realHomeDirectory, relativePath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            // Never clobber data an unsandboxed build already wrote. This happens on
            // machines that ran both a sandboxed release and a local Debug build.
            logger.notice("Skipping \(relativePath, privacy: .public) — destination already exists")
            return
        }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Container and home are on the same volume, so this is a rename: instant,
            // and it needs no extra free space — which matters for the multi-GB models.
            try fileManager.moveItem(at: source, to: destination)
            logger.info("Migrated \(relativePath, privacy: .public) out of the sandbox container")
        } catch {
            logger.error(
                "Failed to migrate \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
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
