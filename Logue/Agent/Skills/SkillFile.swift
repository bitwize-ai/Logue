import Foundation

/// The plain `.md` file a skill exports to and imports from.
///
/// #64 asks that skills "persist, export and import as plain files", which means a person
/// can read one in any editor, write one by hand, and send one to a colleague. So it is
/// frontmatter plus a body — the shape `MarkdownDocumentFile` and `SpaceFile` already use,
/// reusing their reasoning rather than inventing a second format for the same job.
///
/// **Import is the untrusted direction.** A file can arrive from anywhere: a gist, a chat
/// message, a repository of shared skills. Reading one is therefore forgiving about shape
/// and strict about size — an unknown key does not fail the read, and a missing one falls
/// back, but nothing it contains can be unbounded, because the body ends up in a prompt.
///
/// The identifier is deliberately *not* required, which is where this differs from
/// `MarkdownDocumentFile`. A document file without an id is a document Logue has lost track
/// of; a skill file without one is the normal case — somebody wrote it by hand, or exported
/// it from a different machine — and it simply becomes a new skill here.
enum SkillFile {
    static let identifierKey = "_logue_skill_id"
    static let titleKey = "name"
    static let summaryKey = "description"
    static let toolsKey = "tools"

    /// Longest instruction body accepted from a file.
    ///
    /// Larger than what reaches a prompt, so a long skill imports and is truncated at the
    /// prompt rather than being silently cut on the way in — losing someone's text on import
    /// is the one failure here that cannot be undone.
    static let maxBodyCharacters = 32000

    /// Longest tool list accepted. A skill narrows the agent; it does not enumerate a registry.
    static let maxToolNames = 64

    // MARK: - Writing

    /// Renders a skill as a file.
    ///
    /// Key order is fixed so the same skill always produces identical bytes — these files get
    /// checked into repositories, and unstable output would mean a diff on every export.
    static func render(_ skill: AgentSkill) -> String {
        var fields: [(key: String, value: FrontmatterValue)] = [
            (identifierKey, .scalar(skill.id.uuidString)),
            (titleKey, .scalar(skill.title)),
        ]
        if !skill.summary.isEmpty {
            fields.append((summaryKey, .scalar(skill.summary)))
        }
        // Only when the skill actually narrows. An absent key and an empty list mean
        // different things — see `AgentSkill.allowedToolNames` — so an unnarrowed skill must
        // not render `tools: []`, which would read back as "no tools at all".
        if let tools = skill.allowedToolNames {
            fields.append((toolsKey, .list(tools)))
        }
        return MarkdownFrontmatter.render(fields) + "\n" + skill.instructions
    }

    // MARK: - Reading

    /// Reads a skill from a file's text.
    ///
    /// Returns `nil` only when there is nothing usable — no title and no body. A file with
    /// one of the two is a skill someone half-wrote, and refusing it entirely would be less
    /// helpful than importing what is there.
    static func parse(_ text: String) -> AgentSkill? {
        let (fields, body) = MarkdownFrontmatter.parse(text)

        let rawTitle: String = if case let .scalar(value)? = fields[titleKey] {
            value
        } else {
            ""
        }
        let title = SkillName.title(from: rawTitle)
        let instructions = String(DelimitedContent.strip(body).prefix(maxBodyCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty || !instructions.isEmpty else { return nil }

        let summary = if case let .scalar(value)? = fields[summaryKey] {
            String(DisplayText.singleLine(value).prefix(200))
        } else {
            ""
        }

        // An id we cannot read is not an error — it is a file from somewhere else, and it
        // becomes a new skill. Inventing one is exactly right here, and would be exactly
        // wrong for a document, where it risks attaching the file to the wrong record.
        let id: UUID = if case let .scalar(value)? = fields[identifierKey], let parsed = UUID(uuidString: value) {
            parsed
        } else {
            UUID()
        }

        return AgentSkill(
            id: id,
            title: title.isEmpty ? "Untitled skill" : title,
            summary: summary,
            instructions: instructions,
            allowedToolNames: toolNames(from: fields[toolsKey])
        )
    }

    /// The tool list, if the file narrows at all.
    ///
    /// A present-but-empty list is honoured as "no tools", because that is a thing a skill
    /// may legitimately ask for. Only an absent key means "do not narrow".
    private static func toolNames(from value: FrontmatterValue?) -> [String]? {
        switch value {
        case nil:
            nil
        case let .list(items):
            Array(items.map(sanitiseToolName).filter { !$0.isEmpty }.prefix(maxToolNames))
        case let .scalar(single):
            // `tools: read_file_at_path` — a single entry does not have to be written as a
            // list to mean one.
            single.trimmingCharacters(in: .whitespaces).isEmpty
                ? []
                : [sanitiseToolName(single)].filter { !$0.isEmpty }
        }
    }

    /// A tool name is matched against the registry, so anything that could not be a registry
    /// name is dropped rather than carried around as a entry that can never match.
    private static func sanitiseToolName(_ raw: String) -> String {
        String(
            raw.trimmingCharacters(in: .whitespaces)
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                .prefix(MCPToolNaming.maxNameLength)
        )
    }
}
