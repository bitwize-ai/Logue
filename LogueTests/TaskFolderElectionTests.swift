import Foundation
import Testing

@testable import Logue

/// Which marked folder is the tasks folder.
///
/// This rule was got wrong three times inside the filesystem lookup, and every time the tests
/// that were supposed to cover it built a directory tree and asserted the answer — which meant
/// they inherited whatever order `FileManager.enumerator` happened to produce, and one of them
/// passed purely because of the name its fixture used. Testing the rule directly is the point.
@Suite("TaskFolderElection")
struct TaskFolderElectionTests {
    private func candidate(_ name: String, marker: UUID?) -> TaskFolderElection.Candidate {
        TaskFolderElection.Candidate(
            url: URL(fileURLWithPath: "/library").appendingPathComponent(name, isDirectory: true),
            marker: marker
        )
    }

    private func name(of outcome: TaskFolderElection.Outcome) -> String? {
        outcome.chosen?.lastPathComponent
    }

    // MARK: - The simple cases

    @Test("No candidates elects nothing")
    func noCandidates() {
        let outcome = TaskFolderElection.elect(among: [], remembering: nil)
        #expect(outcome.chosen == nil)
        #expect(outcome.wasAmbiguous == false)
    }

    @Test("A sole folder wins whatever its name and whatever is remembered")
    func soleCandidateWins() {
        // The renamed-in-Finder case, which the marker file explicitly invites.
        let outcome = TaskFolderElection.elect(
            among: [candidate("Errands", marker: UUID())], remembering: UUID()
        )
        #expect(name(of: outcome) == "Errands")
        #expect(outcome.wasAmbiguous == false)
    }

    // MARK: - A replacement minted while the real folder was away

    @Test("The remembered folder beats one minted at the conventional name")
    func rememberedBeatsMinted() {
        // Rename the folder, let a reset trash it, let one task write mint a replacement at
        // `Tasks`, then restore the original. Preferring the name here hands the user the
        // near-empty replacement while their real tasks stay reachable from nowhere.
        let real = UUID()
        let outcome = TaskFolderElection.elect(
            among: [candidate("Tasks", marker: UUID()), candidate("Errands", marker: real)],
            remembering: real
        )
        #expect(name(of: outcome) == "Errands")
        #expect(outcome.wasAmbiguous == false, "identity decided this, so nothing was guessed")
    }

    @Test("The result does not depend on the order the folders arrive in")
    func orderDoesNotDecide() {
        // The defect this type replaces: the lookup took the first match from a
        // `FileManager.enumerator`, whose order is a name hash rather than a sort, so the answer
        // depended on what the folders happened to be called.
        let real = UUID()
        let pair = [candidate("Tasks", marker: UUID()), candidate("Errands", marker: real)]

        #expect(name(of: TaskFolderElection.elect(among: pair, remembering: real)) == "Errands")
        #expect(
            name(of: TaskFolderElection.elect(among: pair.reversed(), remembering: real)) == "Errands"
        )
    }

    // MARK: - A copy

    @Test("A copy shares its marker, so the name decides and the guess is recorded")
    func copyFallsBackToTheName() {
        // Duplicating the folder duplicates the marker, so identity matches both and settles
        // nothing. Taking whichever matched first was the bug; falling through is the fix.
        let shared = UUID()
        let outcome = TaskFolderElection.elect(
            among: [candidate("Tasks copy", marker: shared), candidate("Tasks", marker: shared)],
            remembering: shared
        )
        #expect(name(of: outcome) == "Tasks")
        #expect(outcome.wasAmbiguous, "two folders we cannot tell apart must be logged")
    }

    @Test("A copy resolves the same way whichever order it arrives in")
    func copyOrderDoesNotDecide() {
        let shared = UUID()
        let pair = [candidate("Tasks-backup", marker: shared), candidate("Tasks", marker: shared)]

        #expect(name(of: TaskFolderElection.elect(among: pair, remembering: shared)) == "Tasks")
        #expect(
            name(of: TaskFolderElection.elect(among: pair.reversed(), remembering: shared)) == "Tasks"
        )
    }

    // MARK: - Nothing remembered

    @Test("With no memory the conventional name wins, and it counts as a guess")
    func noMemoryFallsBackToTheName() {
        let outcome = TaskFolderElection.elect(
            among: [candidate("Errands", marker: UUID()), candidate("Tasks", marker: UUID())],
            remembering: nil
        )
        #expect(name(of: outcome) == "Tasks")
        #expect(outcome.wasAmbiguous)
    }

    @Test("With no conventional name the earliest path wins, so the answer is stable")
    func noConventionalNameIsStable() {
        // Not a good answer, but a repeatable one: an election that changes between launches
        // moves the user's tasks around.
        let pair = [candidate("Errands", marker: UUID()), candidate("Admin", marker: UUID())]

        #expect(name(of: TaskFolderElection.elect(among: pair, remembering: nil)) == "Admin")
        #expect(name(of: TaskFolderElection.elect(among: pair.reversed(), remembering: nil)) == "Admin")
    }

    @Test("A remembered marker that matches nothing falls through rather than electing nothing")
    func staleMemoryFallsThrough() {
        // The user really did delete the remembered folder. The memory now matches nothing, and
        // that must not leave the library with no tasks folder at all.
        let outcome = TaskFolderElection.elect(
            among: [candidate("Tasks", marker: UUID()), candidate("Errands", marker: UUID())],
            remembering: UUID()
        )
        #expect(name(of: outcome) == "Tasks")
        #expect(outcome.wasAmbiguous)
    }
}
