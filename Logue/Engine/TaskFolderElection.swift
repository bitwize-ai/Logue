import Foundation

/// Which of several marked folders is *the* tasks folder.
///
/// Two folders can carry the task marker for two very different reasons, and telling them apart
/// is the whole job:
///
/// - **A copy.** Duplicating the folder in Finder duplicates its marker, so both carry the
///   *same* identity. Nothing distinguishes them but their names, and the one actually named
///   `Tasks` is the one to keep.
/// - **A replacement.** The user renames the folder, a reset trashes it, and the next task write
///   mints a new one at the conventional name with a *fresh* marker. Restoring the original then
///   puts two different identities side by side — and preferring the name hands the user the
///   near-empty replacement while their real tasks stay reachable from nowhere, because the
///   marker also keeps them out of the document library.
///
/// Pure, and separate from the filesystem, because every previous attempt at this rule was
/// written inside the lookup that walks the disk and could only be tested by building a
/// directory tree — which is why the version before this one elected by `FileManager.enumerator`
/// order without anyone noticing. Enumeration order is a name hash, not a sort: `Tasks-backup`
/// comes before `Tasks`, `Tasks copy` does not.
enum TaskFolderElection {
    struct Candidate: Equatable {
        let url: URL
        /// The identity inside this folder's marker file, if it could be read.
        let marker: UUID?

        init(url: URL, marker: UUID?) {
            self.url = url
            self.marker = marker
        }
    }

    struct Outcome: Equatable {
        let chosen: URL?
        /// Whether the choice came down to a rule of thumb rather than identity.
        ///
        /// The caller logs on this. CLAUDE.md's rule is that ambiguity is never resolved by
        /// guessing silently — a name-based pick among folders we cannot tell apart is exactly
        /// the guess that has to be recorded.
        let wasAmbiguous: Bool
    }

    /// - Parameters:
    ///   - candidates: every folder carrying a readable task marker, in any order. Order must not
    ///     affect the result; the previous rule let it, and a test passed by coincidence of its
    ///     fixture's name.
    ///   - remembered: the marker this app last resolved to, if any.
    ///   - conventionalName: the folder name tasks are created under.
    static func elect(
        among candidates: [Candidate],
        remembering remembered: UUID?,
        conventionalName: String = TaskFile.folderName
    ) -> Outcome {
        guard candidates.count > 1 else {
            return Outcome(chosen: candidates.first?.url, wasAmbiguous: false)
        }

        // Identity decides only when it decides *uniquely*. Two copies share a marker, so a
        // match on both settles nothing and must fall through rather than take whichever came
        // first — the defect this type replaces.
        if let remembered {
            let matching = candidates.filter { $0.marker == remembered }
            if matching.count == 1 {
                return Outcome(chosen: matching[0].url, wasAmbiguous: false)
            }
        }

        // Otherwise the documented rule: the folder actually named `Tasks`, and failing that the
        // first by path so the answer is at least stable across runs.
        let byName = candidates.first { $0.url.lastPathComponent == conventionalName }
        let chosen = byName ?? candidates.min { $0.url.path < $1.url.path }
        return Outcome(chosen: chosen?.url, wasAmbiguous: true)
    }
}
