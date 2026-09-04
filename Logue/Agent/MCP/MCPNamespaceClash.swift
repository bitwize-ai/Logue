import Foundation

/// Whether a server's name would publish its tools under a prefix another server already has.
///
/// Namespaces are *derived* from names — that is what stops a server picking one that
/// shadows a built-in — and the derivation folds: `GitHub`, `git hub` and `GIT-HUB` all give
/// `git_hub`. Two servers landing on the same namespace publish the same names, and
/// `MCPRegistryPlan` resolves that by keeping the first and dropping the rest.
///
/// Which is the right resolution, and an invisible one. The second server sits in Settings
/// enabled, reachable, reporting its tool count — and offers the model nothing, with nothing
/// on screen saying why. So the clash is worth naming *before* it is created, which means
/// answering it while the user is still typing.
///
/// Pure, and outside the view, because a decision made inside a `View` is one the next caller
/// cannot reach — the same reason `AskRouter` is a function rather than a branch in a body.
enum MCPNamespaceClash {
    /// The first of `existing` that folds to the same namespace as `candidate`.
    ///
    /// - Parameters:
    ///   - candidate: the name being typed.
    ///   - existing: the names of the other servers — the caller excludes the one being
    ///     edited, because a server does not clash with itself.
    static func first(for candidate: String, among existing: [String]) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let namespace = MCPToolNaming.namespace(for: trimmed)
        return existing.first { MCPToolNaming.namespace(for: $0) == namespace }
    }
}
