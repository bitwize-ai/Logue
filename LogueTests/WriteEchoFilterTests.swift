import Foundation
@testable import Logue
import Testing

/// Telling our own writes apart from someone else's.
///
/// If this fails open, every save triggers a reload that can replace the editor's text with
/// the version already on disk — lost keystrokes. If it fails closed, real edits made in
/// another app are silently ignored. Both directions are tested.
@Suite("Write echo filter")
struct WriteEchoFilterTests {
    private let file = URL.temporaryDirectory.appendingPathComponent("note.md")

    @Test("An event matching what we wrote is an echo")
    func recognisesOwnWrite() {
        let filter = WriteEchoFilter()
        filter.expect("hello", at: file)

        #expect(filter.isEcho(contents: "hello", at: file))
    }

    /// The failure that costs data: an external edit mistaken for our own is never applied.
    @Test("An event with different content is not an echo")
    func detectsExternalWrite() {
        let filter = WriteEchoFilter()
        filter.expect("hello", at: file)

        #expect(filter.isEcho(contents: "hello, edited elsewhere", at: file) == false)
    }

    @Test("An event for a file we never wrote is not an echo")
    func unknownFileIsNotAnEcho() {
        let filter = WriteEchoFilter()
        #expect(filter.isEcho(contents: "anything", at: file) == false)
    }

    /// Suppression is consumed, not permanent — otherwise a file whose content we once wrote
    /// could never be edited externally to that same text again.
    @Test("An expectation is consumed by the event it explains")
    func expectationIsConsumed() {
        let filter = WriteEchoFilter()
        filter.expect("hello", at: file)

        #expect(filter.isEcho(contents: "hello", at: file))
        #expect(filter.isEcho(contents: "hello", at: file) == false)
    }

    /// A save that produces several events must not leave one of them unexplained.
    @Test("Repeated identical writes are each explained once")
    func countsRepeatedWrites() {
        let filter = WriteEchoFilter()
        filter.expect("hello", at: file)
        filter.expect("hello", at: file)

        #expect(filter.pendingCount == 1)
        #expect(filter.isEcho(contents: "hello", at: file))
        #expect(filter.isEcho(contents: "hello", at: file) == false)
    }

    @Test("Out-of-order events are still matched")
    func matchesOutOfOrder() {
        let filter = WriteEchoFilter()
        filter.expect("first", at: file)
        filter.expect("second", at: file)

        #expect(filter.isEcho(contents: "second", at: file))
        #expect(filter.isEcho(contents: "first", at: file))
    }

    @Test("Expectations are per file")
    func separatesFiles() {
        let filter = WriteEchoFilter()
        let other = URL.temporaryDirectory.appendingPathComponent("other.md")
        filter.expect("hello", at: file)

        #expect(filter.isEcho(contents: "hello", at: other) == false)
        #expect(filter.isEcho(contents: "hello", at: file))
    }

    /// FSEvents reports `/private/tmp/...` where our own URL says `/tmp/...`. Treating those
    /// as different files would make every write under the temp tree look external.
    ///
    /// The file has to exist for the two spellings to resolve to one path, which is the real
    /// case: an event only arrives for a file that is there.
    @Test("A symlinked path matches the same file")
    func matchesAcrossSymlinkedPaths() throws {
        let name = "logue-echo-\(UUID().uuidString).md"
        let viaSymlink = URL(fileURLWithPath: "/tmp/\(name)")
        let resolved = URL(fileURLWithPath: "/private/tmp/\(name)")
        try "hello".write(to: viaSymlink, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: viaSymlink) }

        let filter = WriteEchoFilter()
        filter.expect("hello", at: viaSymlink)

        #expect(filter.isEcho(contents: "hello", at: resolved))
    }

    @Test("Forgetting a file drops its expectations")
    func forgetsFile() {
        let filter = WriteEchoFilter()
        filter.expect("hello", at: file)
        filter.forget(file)

        #expect(filter.isEcho(contents: "hello", at: file) == false)
        #expect(filter.pendingCount == 0)
    }

    @Test("Resetting drops everything")
    func resets() {
        let filter = WriteEchoFilter()
        filter.expect("a", at: file)
        filter.expect("b", at: URL.temporaryDirectory.appendingPathComponent("other.md"))
        filter.reset()

        #expect(filter.pendingCount == 0)
    }

    /// The watcher calls this from a filesystem queue while saves come from the main actor.
    @Test("Concurrent use does not lose or double-count expectations")
    func survivesConcurrentUse() async {
        let filter = WriteEchoFilter()
        let files = (0 ..< 50).map { URL.temporaryDirectory.appendingPathComponent("n\($0).md") }

        await withTaskGroup(of: Void.self) { group in
            for url in files {
                group.addTask { filter.expect("body", at: url) }
            }
        }
        #expect(filter.pendingCount == 50)

        await withTaskGroup(of: Bool.self) { group in
            for url in files {
                group.addTask { filter.isEcho(contents: "body", at: url) }
            }
            var echoes = 0
            for await result in group where result {
                echoes += 1
            }
            #expect(echoes == 50)
        }
        #expect(filter.pendingCount == 0)
    }
}
