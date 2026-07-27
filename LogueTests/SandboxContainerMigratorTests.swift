import Foundation
@testable import Logue
import Testing

/// Covers the two ways the unsandboxing migration could lose or strand user data:
/// stale absolute paths baked into stored meetings, and destinations that already
/// exist on machines that ran both a sandboxed release and a local Debug build.
@Suite("SandboxContainerMigrator")
struct SandboxContainerMigratorTests {
    // MARK: - Scratch Helpers

    /// A unique scratch directory. The migrator only ever looks for the container path
    /// *segment*, so an arbitrary prefix stands in for the real home directory.
    private func makeScratch() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SandboxMigratorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Stale Absolute Paths

    @Test("A container audio path is rewritten once the file has been migrated")
    func rewritesMigratedContainerPath() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let relative = "Library/Application Support/\(AppConstants.bundleID)/Recordings/meeting.m4a"
        let migrated = scratch.appendingPathComponent(relative)
        try write("audio", to: migrated)

        // What a sandboxed 1.0.0 build would have persisted.
        let stale = scratch
            .appendingPathComponent("Library/Containers/\(AppConstants.bundleID)/Data")
            .appendingPathComponent(relative)

        let resolved = SandboxContainerMigrator.resolvingLegacyContainerPath(stale)
        #expect(resolved?.path == migrated.path)
    }

    @Test("A container audio path is left alone when the file was not migrated")
    func keepsUnmigratedContainerPath() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // The file is still in the container — a migration step was skipped as a
        // non-clobber, so the original path is the one that actually works.
        let stale = scratch
            .appendingPathComponent("Library/Containers/\(AppConstants.bundleID)/Data")
            .appendingPathComponent("Library/Application Support/Logue/Recordings/meeting.m4a")
        try write("audio", to: stale)

        #expect(SandboxContainerMigrator.resolvingLegacyContainerPath(stale)?.path == stale.path)
    }

    @Test("Paths outside the container and nil are passed through untouched")
    func passesThroughNonContainerPaths() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let ordinary = scratch.appendingPathComponent("Library/Application Support/Logue/a.m4a")
        try write("audio", to: ordinary)

        #expect(SandboxContainerMigrator.resolvingLegacyContainerPath(ordinary)?.path == ordinary.path)
        #expect(SandboxContainerMigrator.resolvingLegacyContainerPath(nil) == nil)

        let remote = try #require(URL(string: "https://example.com/a.m4a"))
        #expect(SandboxContainerMigrator.resolvingLegacyContainerPath(remote) == remote)
    }

    @Test("Decoding a meeting recorded under the sandbox re-points its audio URL")
    func decodingRewritesStaleAudioURL() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let relative = "Library/Application Support/\(AppConstants.bundleID)/Recordings/meeting.m4a"
        let migrated = scratch.appendingPathComponent(relative)
        try write("audio", to: migrated)

        let stale = scratch
            .appendingPathComponent("Library/Containers/\(AppConstants.bundleID)/Data")
            .appendingPathComponent(relative)

        var meeting = MeetingNote()
        meeting.audioFileURL = stale
        let encoded = try JSONEncoder().encode(meeting)

        let decoded = try JSONDecoder().decode(MeetingNote.self, from: encoded)
        #expect(decoded.audioFileURL?.path == migrated.path)
    }

    // MARK: - Merge / Non-Clobber

    @Test("A missing destination is moved wholesale")
    func movesWhenDestinationIsAbsent() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = scratch.appendingPathComponent("src/models")
        let destination = scratch.appendingPathComponent("dst/models")
        try write("weights", to: source.appendingPathComponent("a.bin"))

        SandboxContainerMigrator.move(source, to: destination, label: "models")

        #expect(read(destination.appendingPathComponent("a.bin")) == "weights")
        #expect(!exists(source))
    }

    @Test("An existing directory is merged, not skipped, so nothing is stranded")
    func mergesIntoExistingDirectory() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = scratch.appendingPathComponent("src/cache")
        let destination = scratch.appendingPathComponent("dst/cache")
        try write("from-container", to: source.appendingPathComponent("only-in-container.bin"))
        try write("existing", to: destination.appendingPathComponent("only-in-home.bin"))

        SandboxContainerMigrator.move(source, to: destination, label: "cache")

        // The non-colliding child migrates instead of being stranded with the parent.
        #expect(read(destination.appendingPathComponent("only-in-container.bin")) == "from-container")
        #expect(read(destination.appendingPathComponent("only-in-home.bin")) == "existing")
    }

    @Test("A colliding file is never overwritten and stays in the container")
    func neverOverwritesExistingFile() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = scratch.appendingPathComponent("src/cache")
        let destination = scratch.appendingPathComponent("dst/cache")
        try write("container-copy", to: source.appendingPathComponent("shared.bin"))
        try write("home-copy", to: destination.appendingPathComponent("shared.bin"))

        SandboxContainerMigrator.move(source, to: destination, label: "cache")

        #expect(read(destination.appendingPathComponent("shared.bin")) == "home-copy")
        // Neither copy is lost — the container one is left behind for recovery.
        #expect(read(source.appendingPathComponent("shared.bin")) == "container-copy")
    }

    @Test("Merging recurses into nested directories that exist on both sides")
    func mergesNestedDirectories() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = scratch.appendingPathComponent("src/Logue")
        let destination = scratch.appendingPathComponent("dst/Logue")
        try write("old", to: source.appendingPathComponent("meetings/a.json"))
        try write("new", to: destination.appendingPathComponent("meetings/b.json"))

        SandboxContainerMigrator.move(source, to: destination, label: "Logue")

        #expect(read(destination.appendingPathComponent("meetings/a.json")) == "old")
        #expect(read(destination.appendingPathComponent("meetings/b.json")) == "new")
    }
}
