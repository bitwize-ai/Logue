import Foundation

/// A named, reusable instruction set the user can invoke by name.
///
/// A skill is text plus a tool budget. What it is *not* is a replacement for how Logue
/// behaves: the app's system prompt still applies underneath, and a skill is layered on top
/// of it. That rule lives with the layering rather than here, but it is why this type holds
/// only what a skill adds — there is nothing on it that could remove something.
///
/// **Its instructions are user content, and they stay user content.** A skill can arrive as
/// a file from anywhere; someone sharing one is sharing a block of text that will be put in
/// front of a model with tools. So `promptSection` is the only way its text is meant to reach
/// a prompt, and it wraps and neutralises rather than trusting the caller to remember —
/// every later caller inherits that instead of re-deciding it.
struct AgentSkill: Identifiable, Codable, Equatable, Sendable {
    /// The tag a skill's instructions are quoted inside.
    static let promptTag = "skill_instructions"

    /// Longest instruction body that reaches a prompt.
    ///
    /// Roughly 1.5k tokens. A skill is layered *on top of* the system prompt and everything
    /// else the turn needs, so it spends context the conversation would otherwise have.
    static let maxInstructionCharacters = 6000

    let id: UUID
    /// What the user calls it, in their own words.
    var title: String
    /// One line saying what it is for. Shown in the picker.
    var summary: String
    /// The instructions themselves.
    var instructions: String
    /// Tools this skill narrows the agent to, by registry name.
    ///
    /// `nil` means "do not narrow" — which is not the same as an empty array, and the
    /// difference is load-bearing. Empty means *no tools*, which is a legitimate thing to
    /// ask for: a skill that only rewrites text has no business calling anything.
    var allowedToolNames: [String]?
    /// Whether this shipped with Logue. Built-ins are readable as examples.
    var isBuiltIn: Bool

    /// How it is invoked, derived from the title rather than stored.
    ///
    /// Derived so the two cannot drift: a stored invocation name would survive a rename and
    /// leave the skill answering to something its title no longer says.
    var invocation: String {
        SkillName.invocation(from: title)
    }

    init(
        id: UUID = .init(),
        title: String,
        summary: String = "",
        instructions: String,
        allowedToolNames: [String]? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.allowedToolNames = allowedToolNames
        self.isBuiltIn = isBuiltIn
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, instructions, allowedToolNames, isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        // Absent is `nil`, not `[]`. A skill written before this field existed did not narrow
        // anything, and reading it as an empty allow-list would silently take every tool away
        // from it.
        allowedToolNames = try container.decodeIfPresent([String].self, forKey: .allowedToolNames)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    /// The skill's text, as it may appear in a prompt.
    ///
    /// Quoted, bounded, and unable to close its own region. A skill file can be written by
    /// anyone and passed around, so its body is third-party text in exactly the way an MCP
    /// server's reply is — and a body containing `</skill_instructions>` would otherwise end
    /// its own region and have the rest read as something Logue said.
    var promptSection: String {
        DelimitedContent.wrap(
            instructions,
            in: Self.promptTag,
            maxCharacters: Self.maxInstructionCharacters
        )
    }
}
