import Foundation

/// Which folder belongs to which space, according to the folders themselves.
///
/// Everything used to answer that by recomputing a path from the space's *name*, and a name is the
/// one thing about a folder that can legitimately differ from what the app has. Three defects came
/// out of that single assumption:
///
/// - A folder the app would spell differently — `-Work`, a name over 60 characters, one holding a
///   character it strips — never matched its own space. Its `_space.md` was never written, so the
///   next scan read the space as having no folder and deleted it, and the one after that created it
///   again with a new identity. The sidebar flickered, and documents inside never filed correctly.
/// - Duplicating a space folder in Finder gave two folders with one identity. Only one resolved by
///   name, so the other was read as a rename, and the space's name alternated between the two
///   folder names on every scan.
/// - Any space whose folder had been renamed between two scans was momentarily nameless.
///
/// So this resolves by the identifier inside `_space.md`, in **both** directions, and falls back to
/// the derived path only for a space that has no folder yet. A name now decides just one thing:
/// what to call a folder at the moment of creating it.
///
/// Built once per operation from a single walk, because the alternative is a folder scan per lookup.
struct SpaceFolderMap: Sendable {
    /// Space identifier → the folder it actually occupies, relative to the root.
    private let componentsByID: [UUID: [String]]
    /// The reverse, keyed on a case-insensitive path so lookups match the filesystem's own rules.
    private let idByPath: [String: UUID]

    /// Folders that claim an identity already claimed by another folder — a duplicated space folder.
    /// Surfaced so a caller can say so rather than behave oddly.
    let duplicatedFolders: [[String]]

    /// Chooses between folders that claim the same space.
    ///
    /// Sorting alone picks the wrong one: `Work copy` sorts before `Work`, because a space sorts
    /// before a slash — so duplicating a folder in Finder handed the space to the copy and renamed it
    /// after the copy. The folder whose name the space already has wins; only when neither matches
    /// does order decide.
    static func preferred(
        _ candidates: [[String]],
        for spaceID: UUID,
        in spaces: [Space]
    ) -> [String]? {
        guard candidates.count > 1 else { return candidates.first }
        guard let space = spaces.first(where: { $0.id == spaceID }) else { return candidates.first }

        return candidates.first { $0.last == space.name } ?? candidates.first
    }

    init(
        componentsByID: [UUID: [String]] = [:],
        duplicatedFolders: [[String]] = [],
        duplicateOwners: [[String]: UUID] = [:]
    ) {
        self.componentsByID = componentsByID
        self.duplicatedFolders = duplicatedFolders

        // Duplicates are in the reverse lookup too, pointing at the same space. A copy of a space
        // folder is not a folder without a space — reading it that way made it a brand-new space
        // sitting alongside the original, sharing its identity.
        var paths = Dictionary(
            componentsByID.map { (Self.key($0.value), $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        for (components, id) in duplicateOwners {
            paths[Self.key(components)] = id
        }
        idByPath = paths
    }

    /// Whether any folder on disk claims this space.
    func hasFolder(for spaceID: UUID) -> Bool {
        componentsByID[spaceID] != nil
    }

    var claimedSpaceIDs: Set<UUID> {
        Set(componentsByID.keys)
    }

    /// Where a space's folder is.
    ///
    /// The folder that claims the space wins over the name-derived path. A space with no folder yet
    /// — one just created in the app — falls back to the derived path, which is exactly the place we
    /// are about to create it.
    func components(forSpace spaceID: UUID?, in spaces: [Space]) -> [String] {
        guard let spaceID else { return [] }
        if let claimed = componentsByID[spaceID] {
            return claimed
        }
        return SpaceFolderLayout.directoryComponents(forSpace: spaceID, in: spaces)
    }

    /// Which space a folder belongs to.
    ///
    /// Identity first, then the name-based resolution for folders that have no `_space.md` — a
    /// folder the user just made, which is about to become a space.
    func spaceID(forComponents components: [String], in spaces: [Space]) -> UUID? {
        guard !components.isEmpty else { return nil }
        if let claimed = idByPath[Self.key(components)] {
            return claimed
        }
        return SpaceFolderLayout.spaceID(forDirectoryComponents: components, in: spaces)
    }

    /// Case-insensitively, because a rename that only changes case is not a different folder on the
    /// filesystems this ships on.
    private static func key(_ components: [String]) -> String {
        components.joined(separator: "/").lowercased()
    }
}
