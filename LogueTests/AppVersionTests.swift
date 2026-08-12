import Foundation
@testable import Logue
import Testing

/// Covers the parsing and ordering that release gating rests on — in particular the
/// double-digit case, which is where comparing version strings instead of numbers
/// starts returning the wrong answer.
@Suite("AppVersion")
struct AppVersionTests {
    // MARK: - Parsing

    @Test("A three-component version parses each component")
    func parsesFullVersion() throws {
        let version = try #require(AppVersion("1.2.3"))
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
    }

    @Test("Absent components default to zero")
    func parsesShortVersions() throws {
        #expect(try #require(AppVersion("1.1")) == AppVersion(major: 1, minor: 1, patch: 0))
        #expect(try #require(AppVersion("2")) == AppVersion(major: 2, minor: 0, patch: 0))
    }

    @Test("A pre-release suffix parses as the release it leads up to")
    func ignoresPreReleaseSuffix() throws {
        #expect(try #require(AppVersion("1.1.0-beta.1")) == AppVersion(major: 1, minor: 1, patch: 0))
        #expect(AppVersion("1.1.0-beta.1") == AppVersion("1.1.0"))
    }

    @Test("Unparseable input is nil rather than zero")
    func rejectsGarbage() {
        // Zero would compare as older than every release and replay the notes forever.
        #expect(AppVersion("") == nil)
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("1.x.0") == nil)
        #expect(AppVersion("1.2.3.4") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("+1.2.3") == nil)
        #expect(AppVersion("-1.2.3") == nil)
    }

    // MARK: - Ordering

    @Test("Versions order by component, not lexically")
    func ordersByComponent() throws {
        let ascending = try ["1.0.0", "1.0.1", "1.1.0", "1.2.0", "2.0.0"]
            .map { try #require(AppVersion($0)) }
        #expect(ascending == ascending.sorted())
    }

    @Test("A tenth minor release is newer than a ninth")
    func ordersDoubleDigitComponents() throws {
        // The reason this type exists: as strings, "1.10.0" < "1.9.0".
        let ninth = try #require(AppVersion("1.9.0"))
        let tenth = try #require(AppVersion("1.10.0"))
        #expect(ninth < tenth)

        let patchNinth = try #require(AppVersion("1.0.9"))
        let patchTenth = try #require(AppVersion("1.0.10"))
        #expect(patchNinth < patchTenth)
    }

    @Test("Build metadata is ignored rather than making the version unreadable")
    func parsesSemverBuildMetadata() throws {
        // Rejecting "+456" made the whole version nil, which reads as "unknown" — and
        // the gate then shows nothing at all, on every launch of that build.
        #expect(try #require(AppVersion("1.2.3+456")) == AppVersion(major: 1, minor: 2, patch: 3))
        // Semver puts metadata after the pre-release suffix, so both have to come off.
        #expect(try #require(AppVersion("1.2.3-beta.1+456")) == AppVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("Equal versions are neither newer nor older")
    func ordersEqualVersions() throws {
        let left = try #require(AppVersion("1.2.3"))
        let right = try #require(AppVersion("1.2.3"))
        #expect(!(left < right))
        #expect(!(right < left))
        #expect(left == right)
    }
}
