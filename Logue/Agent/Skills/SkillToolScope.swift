import Foundation

/// What a skill is allowed to narrow the agent to.
///
/// #64's rule is that a skill can **scope** tools — and scoping has a direction. A skill may
/// take tools away and may never add one, so this is an *intersection* with what was already
/// permitted, never a replacement list.
///
/// Two failures follow from getting that backwards, and both are the kind nobody notices:
///
/// - A skill naming a tool the user turned off in Settings would **re-enable** it. "I never
///   want the agent to do X" has to mean that whoever supplies X, and a shared skill file is
///   the least trustworthy source of all.
/// - A skill naming a tool that does not exist would **conjure** one — a name in the model's
///   tool list that resolves to nothing when called.
///
/// Both are ruled out by construction: the result is a subset of what was handed in. The
/// registry has already applied the per-tool disable list and the MCP gates by then, so each
/// earlier decision stands and this one can only tighten it.
enum SkillToolScope {
    /// The tools a run may use.
    ///
    /// - Parameters:
    ///   - permitted: what the registry already decided this run may use.
    ///   - skill: the skill invoked for this turn, if any.
    static func scoped<Tool>(
        _ permitted: [Tool],
        to skill: AgentSkill?,
        name: (Tool) -> String
    ) -> [Tool] {
        // No skill, or a skill that does not narrow. `nil` and `[]` are deliberately
        // different: a skill asking for no tools is asking for something real.
        guard let allowed = skill?.allowedToolNames else { return permitted }
        let wanted = Set(allowed)
        return permitted.filter { wanted.contains(name($0)) }
    }

    /// The names a skill asked for that it did not get, and why that is worth knowing.
    ///
    /// A skill listing a tool the user has disabled, or one that no longer exists, is not an
    /// error — it is narrowed to nothing and the run continues. But it is the difference
    /// between a skill that is doing less than it says and a skill that is broken, so it is
    /// answerable rather than silent.
    static func unavailable(_ permitted: [String], for skill: AgentSkill?) -> [String] {
        guard let allowed = skill?.allowedToolNames else { return [] }
        let available = Set(permitted)
        return allowed.filter { !available.contains($0) }.sorted()
    }
}
