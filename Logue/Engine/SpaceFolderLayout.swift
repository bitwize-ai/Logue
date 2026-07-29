import Foundation

/// Maps the space hierarchy onto directories, in both directions.
///
/// A space becomes a directory and a sub-space a sub-directory, so the folder on disk
/// reads the way the sidebar does. Space names are user-controlled and become real
/// directory names, so every component is sanitised — the same path-safety boundary
/// `DocumentFilename` guards for files.
enum SpaceFolderLayout {
    /// Maximum nesting mirrored.
    ///
    /// Bounds both a pathological hierarchy and a corrupted parent chain, and keeps
    /// the resulting path well inside filesystem length limits.
    static let maxDepth = 12

    private static let fallbackComponent = "Untitled Space"

    /// How many levels down a space sits, counting itself. `nil` is the top level, so zero.
    ///
    /// Distinct from `directoryComponents(forSpace:in:).count`, which clamps to nothing past
    /// `maxDepth` — so a space *deeper* than the cap reads there as depth zero. Anything deciding
    /// how much room is left has to ask this instead, or it concludes a too-deep space has the
    /// full allowance available below it.
    ///
    /// Uncapped, and cycle-guarded the same way, because the answer for a broken chain should be a
    /// number rather than a hang.
    static func depth(ofSpace spaceID: UUID?, in spaces: [Space]) -> Int {
        guard let spaceID else { return 0 }

        let byID = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var visited: Set<UUID> = []
        var current: UUID? = spaceID
        var depth = 0

        while let id = current, visited.insert(id).inserted {
            guard let space = byID[id] else { break }
            depth += 1
            current = space.parentID
        }
        return depth
    }

    // MARK: - Space → directories

    /// Directory names for a space, outermost first.
    ///
    /// Returns empty for `nil` or an unknown space, which places the document at the
    /// documents folder root rather than inventing a directory.
    static func directoryComponents(forSpace spaceID: UUID?, in spaces: [Space]) -> [String] {
        guard let spaceID else { return [] }

        let byID = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard byID[spaceID] != nil else { return [] }

        // Walk up to the root, guarding against a cycle in the parent chain: a
        // corrupted hierarchy must not hang the app.
        var chain: [Space] = []
        var visited: Set<UUID> = []
        var current: UUID? = spaceID

        var isDeeperThanMaxDepth = false

        while let id = current, visited.insert(id).inserted {
            if chain.count >= maxDepth {
                isDeeperThanMaxDepth = true
                break
            }
            // A parent that is not in `spaces` ends the walk: a space whose parent record is gone
            // is treated as top level, which is the least surprising reading of a broken chain.
            guard let space = byID[id] else { break }
            chain.append(space)
            current = space.parentID
        }

        // A hierarchy deeper than the cap yields no path at all. Stopping mid-walk used to return
        // the deepest components and silently drop the outermost ones, producing a path that does
        // not exist — which reads downstream as "this space has no folder", and the answer to that
        // was to delete the space and trash everything in it. Placing its documents at the root is
        // visibly wrong and harmless, which is the right way to fail.
        guard !isDeeperThanMaxDepth else { return [] }

        return chain.reversed().map { component(for: $0, in: spaces) }
    }

    // MARK: - Directories → space

    /// The space a directory path refers to, or `nil` when it does not fully resolve.
    ///
    /// Resolves strictly: a path whose last component is unknown yields `nil` rather
    /// than the nearest ancestor, so a caller never files a document into the wrong
    /// parent.
    static func spaceID(forDirectoryComponents components: [String], in spaces: [Space]) -> UUID? {
        guard !components.isEmpty else { return nil }

        var parentID: UUID?
        for component in components {
            guard let match = child(named: component, of: parentID, in: spaces) else { return nil }
            parentID = match.id
        }
        return parentID
    }

    // MARK: - Private

    /// A sanitised, sibling-unique directory name for a space.
    ///
    /// Two siblings sharing a name would otherwise map to one directory and silently
    /// merge, so the later one is disambiguated by a stable prefix of its identifier.
    private static func component(for space: Space, in spaces: [Space]) -> String {
        let base = sanitised(space.name)

        // Ordered by creation, then identifier: two spaces created in the same instant
        // still order deterministically, so the disambiguated name is stable.
        let clashesEarlier = spaces.contains { other in
            other.id != space.id
                && other.parentID == space.parentID
                && sanitised(other.name).caseInsensitiveCompare(base) == .orderedSame
                && sortsBefore(other, space)
        }

        guard clashesEarlier else { return base }
        return "\(base) (\(space.id.uuidString.prefix(8)))"
    }

    /// Deterministic ordering for two spaces, independent of timestamp resolution.
    private static func sortsBefore(_ lhs: Space, _ rhs: Space) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func child(named name: String, of parentID: UUID?, in spaces: [Space]) -> Space? {
        spaces.first {
            $0.parentID == parentID
                && component(for: $0, in: spaces).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Strips anything unsafe or confusing from a directory name.
    private static func sanitised(_ name: String) -> String {
        var cleaned = ""
        for character in name {
            if character.isNewline {
                continue
            }
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                continue
            }
            if "/:\\?%*|\"<>".contains(character) {
                continue
            }
            cleaned.append(character)
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") || cleaned.hasPrefix("-") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return fallbackComponent }
        return String(cleaned.prefix(60))
    }
}
