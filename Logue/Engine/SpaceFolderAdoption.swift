import Foundation

/// Which folders on disk have no space yet.
///
/// Pure, because the failure it prevents already happened once: creating a space for a
/// folder that *did* have one, which then wrote a differently-named folder, which looked
/// like another new folder, and so on — a library that grew every time it was scanned. The
/// check that a folder already resolves has to be exactly the check the writer uses, so both
/// go through `MirrorLayout`.
enum SpaceFolderAdoption {
    /// A space that needs creating, named by its folder.
    struct Creation: Equatable, Sendable {
        let name: String
        let parentComponents: [String]

        var components: [String] {
            parentComponents + [name]
        }
    }

    /// What to do about a folder that has no space under its current name.
    enum Resolution: Equatable, Sendable {
        /// A space we already have, whose folder was renamed or moved.
        case rename(id: UUID, to: String, parentComponents: [String])
        /// A folder with no space. `id` is the one its `_space.md` claims, or `nil` for a
        /// folder that has never been one.
        case create(id: UUID?, name: String, parentComponents: [String])
    }

    /// Decides whether a folder is a new space or a renamed one.
    ///
    /// This is what makes renaming a folder in Finder a rename rather than a replacement: the
    /// `_space.md` inside still names the same space, so the space follows the folder instead
    /// of being recreated and losing its icon, colour and place in the sidebar.
    ///
    /// A claimed identifier that matches nothing — a folder restored from a backup, say — is
    /// kept rather than replaced, so restoring the folder restores the space it was.
    static func resolve(_ creation: Creation, claimedID: UUID?, in spaces: [Space]) -> Resolution {
        if let claimedID, spaces.contains(where: { $0.id == claimedID }) {
            return .rename(
                id: claimedID, to: creation.name, parentComponents: creation.parentComponents
            )
        }
        return .create(
            id: claimedID, name: creation.name, parentComponents: creation.parentComponents
        )
    }

    /// Folders with no space, ordered so every parent is created before its children.
    ///
    /// Ancestors are included even when only a leaf was passed: someone can create
    /// `Work/Projects/Q3` in one drag, and creating `Q3` under nothing would flatten it.
    static func creations(forDirectoryPaths paths: [[String]], in spaces: [Space]) -> [Creation] {
        // Every prefix of every path, so ancestors are considered too.
        var candidates: Set<[String]> = []
        for path in paths {
            for depth in 1 ... max(path.count, 1) where depth <= path.count {
                candidates.insert(Array(path.prefix(depth)))
            }
        }

        // Shallowest first so a parent is always created before its children; name-ordered
        // within a depth so the result does not depend on enumeration order.
        let ordered = candidates.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count < rhs.count : lhs.joined(separator: "/") < rhs.joined(separator: "/")
        }

        var creations: [Creation] = []
        var planned: Set<[String]> = []

        for components in ordered {
            guard let name = components.last else { continue }
            // Already a space, or already about to become one on this pass.
            if MirrorLayout.spaceID(forDirectoryComponents: components, in: spaces) != nil
                || planned.contains(components)
            {
                continue
            }
            planned.insert(components)
            creations.append(Creation(name: name, parentComponents: components.dropLast()))
        }

        return creations
    }
}
