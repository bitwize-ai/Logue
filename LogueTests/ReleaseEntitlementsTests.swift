import Foundation
@testable import Logue
import Testing

/// Guards the entitlement that broke cross-app features in 1.0.0.
///
/// Release shipped with `com.apple.security.app-sandbox = true`, and a sandboxed
/// process cannot be an Accessibility API client: `AXIsProcessTrustedWithOptions`
/// returns false, no prompt appears, and TCC never lists the app under
/// Privacy & Security → Accessibility (issue #22). Re-enabling the sandbox silently
/// kills ⌘⌃I, global hotkeys, Command Center and text replacement — nothing fails
/// loudly at build time, so it is checked here instead.
@Suite("Release entitlements")
struct ReleaseEntitlementsTests {
    /// Repo root, derived from this file's location so the test does not depend on
    /// the test bundle's resources or the working directory.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LogueTests/
            .deletingLastPathComponent() // repo root
    }

    private func entitlements(named name: String) throws -> [String: Any] {
        let url = Self.repositoryRoot
            .appendingPathComponent("Logue")
            .appendingPathComponent("Resources")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(parsed as? [String: Any], "\(name) is not a plist dictionary")
    }

    @Test("Release is not sandboxed, so it can be an Accessibility API client")
    func releaseIsNotSandboxed() throws {
        let plist = try entitlements(named: "Logue.release.entitlements")
        let sandbox = try #require(
            plist["com.apple.security.app-sandbox"] as? Bool,
            "Release entitlements must state the sandbox setting explicitly"
        )
        #expect(sandbox == false, "Enabling the sandbox breaks every Logue/CrossApp feature — see issue #22")
    }

    @Test("Debug is not sandboxed either, so Debug and Release behave the same")
    func debugIsNotSandboxed() throws {
        let plist = try entitlements(named: "Logue.entitlements")
        let sandbox = try #require(plist["com.apple.security.app-sandbox"] as? Bool)
        #expect(sandbox == false)
    }

    @Test("Release keeps the hardened-runtime exceptions MLX needs")
    func releaseKeepsHardenedRuntimeExceptions() throws {
        let plist = try entitlements(named: "Logue.release.entitlements")
        for key in [
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-library-validation",
        ] {
            #expect(plist[key] as? Bool == true, "Release is missing \(key)")
        }
    }

    @Test("Release drops the sandbox-only Sparkle mach-lookup exception")
    func releaseDropsSandboxOnlySparkleException() throws {
        let plist = try entitlements(named: "Logue.release.entitlements")
        #expect(
            plist["com.apple.security.temporary-exception.mach-lookup.global-name"] == nil,
            "Sparkle's XPC mach-lookup exception is sandbox-only and inert without the sandbox"
        )
    }
}
