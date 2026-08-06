import Foundation

/// A marketing version (`CFBundleShortVersionString`), parsed so releases can be ordered.
///
/// Ordering is the whole reason this type exists. Comparing the strings instead puts
/// "1.10.0" below "1.9.0", which would silently stop showing release notes to everyone
/// past a tenth minor release.
struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses "1", "1.2", "1.2.3" and "1.2.3-beta.1"; absent components are zero, and a
    /// pre-release suffix orders as the release it leads up to, so a beta tester is not
    /// shown the same notes again on the final build.
    ///
    /// Returns nil for anything else, so a garbled Info.plist reads as "unknown" rather
    /// than as 0.0.0 — which would compare as older than every real release and replay
    /// the notes on every launch.
    init?(_ string: String) {
        let core = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = core.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            // `Int(_:)` alone would accept "+2" and " 2"; a version component is digits.
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part)
            else { return nil }
            numbers.append(value)
        }

        guard let first = numbers.first else { return nil }
        major = first
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    // MARK: - This build

    /// The running app's marketing version, or nil if Info.plist carries something
    /// unparseable. Callers that gate behaviour must treat nil as "do nothing".
    static var current: AppVersion? {
        AppVersion(currentString)
    }

    /// The raw string, for display. Empty when absent — callers show it verbatim, and
    /// an empty version reads better in an About pane than a fabricated "0.0.0".
    static var currentString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
