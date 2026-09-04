import Foundation

/// Keeping "never let the agent do X" true when the server providing X is renamed.
///
/// A server's tools are published under a namespace derived from its **name**
/// (`MCPToolNaming`), and the per-tool disable list is keyed on the published name — the one
/// the user saw in Settings when they turned the tool off. Those two facts together mean a
/// rename silently re-enables everything: `github__delete_repo` becomes
/// `gitlab__delete_repo`, which is not on the list, so the tool is offered again.
///
/// That is the worst direction for a mistake of this kind to go. "I never want the agent to
/// do this" has to survive an edit that had nothing to do with it, and the user gets no
/// signal — the tool simply becomes available again, under a name they have never seen.
///
/// Pure, and separate from both the store and the view, because it is a rule rather than a
/// screen: whatever eventually renames a server has to apply it, and a copy inside one form
/// would not be applied by the next caller.
enum MCPRenameMigration {
    /// The disable list, rewritten for a server that is changing name.
    ///
    /// Only entries under the old server's namespace move. Everything else — built-ins, and
    /// other servers' tools — is returned untouched.
    ///
    /// - Note: if two servers fold to the same namespace (`GitHub` and `git hub` both give
    ///   `git_hub`), an entry cannot be attributed to one of them and the other's disabled
    ///   tools move too. That is the same ambiguity `MCPRegistryPlan` resolves by dropping
    ///   the colliding tool, and it errs the same way: towards the tool staying *off*, which
    ///   is the direction that cannot surprise anyone.
    static func remapped(disabled: Set<String>, from oldName: String, to newName: String) -> Set<String> {
        let oldNamespace = MCPToolNaming.namespace(for: oldName)
        let newNamespace = MCPToolNaming.namespace(for: newName)
        guard oldNamespace != newNamespace else { return disabled }

        return Set(disabled.map { entry in
            guard let parts = MCPToolNaming.split(entry), parts.namespace == oldNamespace else {
                return entry
            }
            // Rebuilt through `published` rather than by pasting the halves together, so the
            // result obeys the same length bound as the name the registry will look for. A
            // hand-assembled name that exceeds it would never match anything.
            return MCPToolNaming.published(serverName: newName, toolName: parts.tool)
        })
    }
}
