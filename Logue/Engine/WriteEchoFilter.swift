import CryptoKit
import Foundation

/// Drops filesystem events caused by Logue's own writes.
///
/// Without this, every save fires a change event, which triggers a read, which applies a
/// change, which triggers a save. The loop is not merely wasteful: a read landing between
/// two keystrokes replaces the editor's text with the older file, so it loses typing.
///
/// Matching is on **content**, not on path or time. A path-based filter cannot tell our
/// write from a user's write to the same file moments later, and a time-based one silently
/// widens into a window where real edits are dropped. If the bytes on disk are the bytes we
/// wrote, the event is ours; if they are not, someone else wrote and we must react — which
/// stays true no matter how long the write took or how many events it produced.
///
/// `@unchecked Sendable`: every access goes through `lock`, and the only stored state is a
/// dictionary of value types.
final class WriteEchoFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var expected: [String: Set<String>] = [:]

    /// Records what we are about to write, so the resulting event can be recognised.
    func expect(_ contents: String, at url: URL) {
        let key = Self.key(for: url)
        let digest = Self.digest(of: contents)
        lock.lock()
        defer { lock.unlock() }
        expected[key, default: []].insert(digest)
    }

    /// Whether an event for this file was caused by us.
    ///
    /// Consumes the expectation: a second event carrying the same content is a genuine
    /// external write — someone saved the same text again — and re-suppressing it forever
    /// would make that file permanently unwatchable.
    func isEcho(contents: String, at url: URL) -> Bool {
        let key = Self.key(for: url)
        let digest = Self.digest(of: contents)
        lock.lock()
        defer { lock.unlock() }

        guard var digests = expected[key], digests.remove(digest) != nil else { return false }
        if digests.isEmpty {
            expected.removeValue(forKey: key)
        } else {
            expected[key] = digests
        }
        return true
    }

    /// Forgets a file, for when it is deleted or moved away.
    func forget(_ url: URL) {
        let key = Self.key(for: url)
        lock.lock()
        defer { lock.unlock() }
        expected.removeValue(forKey: key)
    }

    /// Forgets everything, for when the folder stops being watched.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        expected.removeAll()
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return expected.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Private

    /// Standardised so `/tmp/x.md` and `/private/tmp/x.md` are one key: FSEvents reports
    /// resolved paths, while our own writes use whatever URL the caller built.
    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func digest(of contents: String) -> String {
        SHA256.hash(data: Data(contents.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
