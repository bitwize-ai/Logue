import Foundation
import Testing

@testable import Logue

/// Which folder the app believes is its own.
///
/// This rule was got wrong in three consecutive rounds of review, every time because it lived in
/// a static reading `UserDefaults.standard` that no test could reach. Every case below fails
/// against one of those three shapes.
@Suite("TaskFolderMemory")
struct TaskFolderMemoryTests {
    /// A defaults suite per test, so nothing here touches the app's own preferences.
    private final class IsolatedDefaults {
        let name = "logue-memory-\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name) ?? .standard }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
    }

    private func memory(_ isolated: IsolatedDefaults) -> TaskFolderMemory {
        TaskFolderMemory(defaults: isolated.defaults, key: "lastTaskFolderMarker")
    }

    @Test("A fresh app remembers nothing")
    func startsEmpty() {
        let isolated = IsolatedDefaults()
        #expect(memory(isolated).remembered == nil)
        _ = isolated
    }

    @Test("The first folder it settles on is remembered")
    func learnsOnce() {
        let isolated = IsolatedDefaults()
        let marker = UUID()

        #expect(memory(isolated).rememberIfUnknown(marker))
        #expect(memory(isolated).remembered == marker)
        _ = isolated
    }

    @Test("A later folder does not overwrite the one it learned")
    func doesNotRelearn() {
        // The defect that made the memory useless: rewriting on every resolve. With the real
        // folder in the Trash, a write mints a replacement; on the next launch that replacement
        // is the only marked folder, so it was returned *and* remembered — and restoring the
        // original then lost the election exactly as it had before the memory existed. A
        // relaunch was precisely what wiped the memory meant to survive one.
        let isolated = IsolatedDefaults()
        let real = UUID()
        let minted = UUID()

        memory(isolated).rememberIfUnknown(real)
        #expect(memory(isolated).rememberIfUnknown(minted) == false)
        #expect(memory(isolated).remembered == real)
        _ = isolated
    }

    @Test("Nothing is learned from a folder with no marker")
    func ignoresAnUnmarkedFolder() {
        let isolated = IsolatedDefaults()
        #expect(memory(isolated).rememberIfUnknown(nil) == false)
        #expect(memory(isolated).remembered == nil)
        _ = isolated
    }

    @Test("Forgetting lets it learn again")
    func forgettingAllowsRelearning() {
        // The other half, and the one the write-once rule opened: a folder the user told the app
        // to throw away must stop being the one it looks for, or restoring it for some unrelated
        // reason hands them back a library they had deleted.
        let isolated = IsolatedDefaults()
        let old = UUID()
        let new = UUID()

        memory(isolated).rememberIfUnknown(old)
        memory(isolated).forget()
        #expect(memory(isolated).remembered == nil)

        #expect(memory(isolated).rememberIfUnknown(new))
        #expect(memory(isolated).remembered == new)
        _ = isolated
    }

    @Test("Forgetting what it never knew is not an error")
    func forgettingNothingIsSafe() {
        let isolated = IsolatedDefaults()
        memory(isolated).forget()
        #expect(memory(isolated).remembered == nil)
        _ = isolated
    }

    @Test("Learning, forgetting and relearning in order leaves the last folder")
    func theOrderOfOperationsIsWhatDecides() {
        // The ordering bug this suite exists to catch: `clearAllData` forgot the marker *before*
        // resolving the folder it was about to trash — and resolving it is itself what teaches
        // the memory, so the forget was undone by the very next line and the trashed folder was
        // remembered again.
        let isolated = IsolatedDefaults()
        let trashed = UUID()
        let replacement = UUID()

        memory(isolated).rememberIfUnknown(trashed)
        // Forget-then-resolve, which is the wrong order: the resolve re-learns the old folder.
        memory(isolated).forget()
        memory(isolated).rememberIfUnknown(trashed)
        #expect(memory(isolated).remembered == trashed, "this is the sequence that failed")

        // Resolve-then-forget, which is the order the code now uses.
        memory(isolated).forget()
        #expect(memory(isolated).remembered == nil)
        #expect(memory(isolated).rememberIfUnknown(replacement))
        #expect(memory(isolated).remembered == replacement)
        _ = isolated
    }
}
