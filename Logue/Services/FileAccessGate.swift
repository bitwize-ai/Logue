import AppKit
import Foundation
import os.log

/// Sandbox-safe file access gate. Resolves an arbitrary POSIX path the
/// agent receives (from a tool argument) into a URL the app is allowed
/// to touch.
///
/// Strategy:
/// - **Debug builds (sandbox off):** every path resolves directly. No
///   bookmarks needed — `FileManager` already has full filesystem access.
/// - **Release builds (sandbox on):** the first time the agent touches a
///   path outside the app's container, we present an `NSOpenPanel`
///   pre-populated with that path so the user explicitly grants access.
///   The resulting security-scoped bookmark is saved to UserDefaults and
///   re-used on subsequent calls.
///
/// Bookmarks are per-folder, not per-file — granting `~/Documents` once
/// covers everything beneath it, matching how Files-app permission grants
/// work on iOS.
@MainActor
final class FileAccessGate {
    static let shared = FileAccessGate()
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "FileAccessGate")

    private static let bookmarksKey = "files.scopedBookmarks"

    private init() {}

    /// Returns a usable URL for `path`, prompting the user via `NSOpenPanel`
    /// if no scoped bookmark covers it. Throws when the user cancels or the
    /// path doesn't exist.
    func resolve(path: String) async throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAccessError.notFound(path)
        }
        // 1. Already covered by an existing bookmark? Just resume access.
        if let resolved = try resolveExistingBookmark(for: url) {
            return resolved
        }
        // 2. Sandboxing off (debug build): direct access works.
        if !isSandboxed {
            return url
        }
        // 3. Ask the user to grant the parent folder.
        let granted = try await promptForFolder(initial: url)
        try storeBookmark(for: granted)
        return url
    }

    /// True when the running process is sandboxed. Read once per launch.
    private lazy var isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    // MARK: - Bookmark resolution

    private func resolveExistingBookmark(for url: URL) throws -> URL? {
        let bookmarks = storedBookmarks()
        for (storedPath, data) in bookmarks {
            // Check if stored bookmark covers this URL by prefix match.
            // We only return the bookmark if the resolution succeeds —
            // stale bookmarks are pruned silently.
            guard url.path.hasPrefix(storedPath) else { continue }
            var stale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                if stale {
                    logger.warning("Stale bookmark for \(storedPath, privacy: .public); re-prompting")
                    continue
                }
                _ = resolved.startAccessingSecurityScopedResource()
                return url
            } catch {
                logger.warning("Bookmark resolve failed for \(storedPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    @MainActor
    private func promptForFolder(initial: URL) async throws -> URL {
        let panel = NSOpenPanel()
        panel.message = "Grant Logue access to this folder so the agent can read or write files inside it"
        panel.prompt = "Grant access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = initial.deletingLastPathComponent()
        let response = await panel.beginSheetModalSafely()
        guard response == .OK, let url = panel.url else {
            throw FileAccessError.userDeclined
        }
        return url
    }

    private func storeBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var bookmarks = storedBookmarks()
        bookmarks[url.path] = data
        let pairs = bookmarks.map { ScopedBookmark(path: $0.key, data: $0.value) }
        let encoded = try JSONEncoder().encode(pairs)
        UserDefaults.standard.set(encoded, forKey: Self.bookmarksKey)
    }

    private func storedBookmarks() -> [String: Data] {
        guard let raw = UserDefaults.standard.data(forKey: Self.bookmarksKey),
              let pairs = try? JSONDecoder().decode([ScopedBookmark].self, from: raw)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.path, $0.data) })
    }

    private struct ScopedBookmark: Codable {
        let path: String
        let data: Data
    }

    enum FileAccessError: LocalizedError {
        case notFound(String)
        case userDeclined
        case notDirectory(String)
        case notFile(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case let .notFound(path): "File not found: \(path)"
            case .userDeclined: "Access denied — user did not grant permission"
            case let .notDirectory(path): "Not a directory: \(path)"
            case let .notFile(path): "Not a file: \(path)"
            case let .writeFailed(detail): "Write failed: \(detail)"
            }
        }
    }
}

// MARK: - NSOpenPanel async helper

private extension NSOpenPanel {
    /// Wraps `beginSheetModal` in async/await with main-actor safety. The
    /// modal is always presented from the main app window when one is
    /// available; falls back to a free-standing modal otherwise.
    func beginSheetModalSafely() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            } else {
                let response = runModal()
                continuation.resume(returning: response)
            }
        }
    }
}
