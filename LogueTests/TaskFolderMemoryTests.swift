import Foundation
import Testing

@testable import Logue

/// Which folder the app believes is its own.
///
/// Kept honest by being driven directly; see `TaskFolderLocator`'s header for why this rule has
/// its own type at all.
///
/// `doesNotRelearn` and `forgettingAllowsRelearning` are the two that discriminate — they fail
/// against refresh-on-every-resolve and against write-once-never-forget respectively. The rest
/// are smoke tests over the type's surface, which is what they are worth. The *sequence* those
/// two shapes broke lives in `TaskFolderLocatorTests`, against a real folder.
@Suite("TaskFolderMemory")
struct TaskFolderMemoryTests {
    private func withScratchMemory(_ body: (TaskFolderMemory) throws -> Void) throws {
        try withScratchDefaults(label: "logue-memory") { defaults in
            try body(
                TaskFolderMemory(
                    defaults: defaults,
                    key: AppConstants.UserDefaultsKeys.lastTaskFolderMarker
                )
            )
        }
    }

    @Test("A fresh app remembers nothing")
    func startsEmpty() throws {
        try withScratchMemory { memory in
            #expect(memory.remembered == nil)
        }
    }

    @Test("The first folder it settles on is remembered")
    func learnsOnce() throws {
        try withScratchMemory { memory in
            let marker = UUID()

            #expect(memory.rememberIfUnknown(marker))
            #expect(memory.remembered == marker)
        }
    }

    @Test("A later folder does not overwrite the one it learned")
    func doesNotRelearn() throws {
        try withScratchMemory { memory in
            // The defect that made the memory useless: rewriting on every resolve. With the real
            // folder in the Trash, a write mints a replacement; on the next launch that replacement
            // is the only marked folder, so it was returned *and* remembered — and restoring the
            // original then lost the election exactly as it had before the memory existed. A
            // relaunch was precisely what wiped the memory meant to survive one.
            let real = UUID()
            let minted = UUID()

            memory.rememberIfUnknown(real)
            #expect(memory.rememberIfUnknown(minted) == false)
            #expect(memory.remembered == real)
        }
    }

    @Test("Nothing is learned from a folder with no marker")
    func ignoresAnUnmarkedFolder() throws {
        try withScratchMemory { memory in
            #expect(memory.rememberIfUnknown(nil) == false)
            #expect(memory.remembered == nil)
        }
    }

    @Test("Forgetting lets it learn again")
    func forgettingAllowsRelearning() throws {
        try withScratchMemory { memory in
            // The other half, and the one the write-once rule opened: a folder the user told the app
            // to throw away must stop being the one it looks for, or restoring it for some unrelated
            // reason hands them back a library they had deleted.
            let old = UUID()
            let new = UUID()

            memory.rememberIfUnknown(old)
            memory.forget()
            #expect(memory.remembered == nil)

            #expect(memory.rememberIfUnknown(new))
            #expect(memory.remembered == new)
        }
    }

    @Test("Forgetting what it never knew is not an error")
    func forgettingNothingIsSafe() throws {
        try withScratchMemory { memory in
            memory.forget()
            #expect(memory.remembered == nil)
        }
    }
}
