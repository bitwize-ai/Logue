import SwiftUI

/// Builds a hierarchical "Move to" submenu that mirrors the space tree,
/// matching Apple Notes' folder-tree style for "Move to" actions.
/// U8: Replaced AnyView with @ViewBuilder to preserve SwiftUI diff identity.
struct HierarchicalSpaceMenu: View {
    let currentSpaceID: UUID?
    let excludeSpaceID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(SpaceStore.self) private var spaceStore

    init(
        currentSpaceID: UUID?,
        excludeSpaceID: UUID? = nil,
        onSelect: @escaping (UUID?) -> Void
    ) {
        self.currentSpaceID = currentSpaceID
        self.excludeSpaceID = excludeSpaceID
        self.onSelect = onSelect
    }

    var body: some View {
        if currentSpaceID != nil {
            Button {
                onSelect(nil)
            } label: {
                Label("Remove from Space", systemImage: "arrow.uturn.backward")
            }
            Divider()
        }
        ForEach(spaceStore.topLevelSpaces) { space in
            SpaceMenuNode(
                space: space,
                currentSpaceID: currentSpaceID,
                excludeSpaceID: excludeSpaceID,
                spaceStore: spaceStore,
                onSelect: onSelect
            )
        }
    }
}

/// Recursive view struct that replaces AnyView type erasure.
private struct SpaceMenuNode: View {
    let space: Space
    let currentSpaceID: UUID?
    let excludeSpaceID: UUID?
    let spaceStore: SpaceStore
    let onSelect: (UUID?) -> Void

    var body: some View {
        let children = spaceStore.children(of: space.id)

        if space.id == excludeSpaceID {
            EmptyView()
        } else if space.id == currentSpaceID {
            if !children.isEmpty {
                Menu {
                    ForEach(children) { child in
                        SpaceMenuNode(
                            space: child,
                            currentSpaceID: currentSpaceID,
                            excludeSpaceID: excludeSpaceID,
                            spaceStore: spaceStore,
                            onSelect: onSelect
                        )
                    }
                } label: {
                    Label(space.name, systemImage: space.icon ?? "folder")
                }
            }
        } else if children.isEmpty {
            Button {
                onSelect(space.id)
            } label: {
                Label(space.name, systemImage: space.icon ?? "folder")
            }
        } else {
            Menu {
                Button {
                    onSelect(space.id)
                } label: {
                    Label("Move Here", systemImage: "arrow.right")
                }
                Divider()
                ForEach(children) { child in
                    SpaceMenuNode(
                        space: child,
                        currentSpaceID: currentSpaceID,
                        excludeSpaceID: excludeSpaceID,
                        spaceStore: spaceStore,
                        onSelect: onSelect
                    )
                }
            } label: {
                Label(space.name, systemImage: space.icon ?? "folder")
            }
        }
    }
}
