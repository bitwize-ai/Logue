import Foundation

/// The skills Logue ships with.
///
/// These are documentation as much as they are features. #64 asks that the built-ins be
/// "readable as examples", which is the reason each one is written the way someone's own
/// skill should be: a short summary, instructions that say what to do rather than what to
/// be, and a tool list that is *narrow* — the point being that narrowing is normal, not an
/// advanced option.
///
/// Ids are fixed so an edited built-in can be told apart from a user's own skill across
/// launches, and so `SkillStore.restore` can find the original.
enum SkillCatalog {
    /// A built-in's fixed identity.
    ///
    /// Force-unwrapped deliberately, and the project rule allows it here: these are
    /// compile-time constants written in this file, so a bad one is a typo caught the first
    /// time anything reads `builtIns` — not a runtime condition a caller could hit.
    private static func id(_ raw: String) -> UUID {
        // swiftlint:disable:next force_unwrapping
        UUID(uuidString: raw)!
    }

    static let builtIns: [AgentSkill] = [
        AgentSkill(
            id: id("6E1B0F5A-0000-4000-8000-000000000001"),
            title: "Meeting follow-up",
            summary: "Turn a meeting into the messages and tasks it actually implies.",
            instructions: """
            Read the meeting the user names and produce, in this order:

            1. The decisions that were actually made. Not topics discussed — decisions, with
               who made each one. If none were made, say so rather than inventing them.
            2. What each person committed to, in their own words where the transcript has
               them, and only where someone actually committed. Leave out anything that was
               merely suggested.
            3. What is still open, and who has to answer it.

            Do not summarise the meeting. The user was in it. Anything they could have
            written down themselves while sitting there is not worth telling them.
            """,
            allowedToolNames: ["get_meeting", "search_meetings", "add_reminder"],
            isBuiltIn: true
        ),
        AgentSkill(
            id: id("6E1B0F5A-0000-4000-8000-000000000002"),
            title: "Tighten this",
            summary: "Cut a document to what it is actually saying, without changing what that is.",
            instructions: """
            Rewrite the document the user names so it says the same things in less space.

            - Remove sentences that restate the previous one.
            - Replace an abstraction with the concrete thing it stands for, where the
              document already contains the concrete thing.
            - Keep every claim, number, name and caveat. If a cut would lose one, do not
              make it.

            Return the rewritten text and, separately, a short list of what you removed, so
            the user can put back anything you were wrong about. Never present the rewrite
            as strictly better — say what the trade was.
            """,
            allowedToolNames: ["get_document", "rephrase_text"],
            isBuiltIn: true
        ),
        AgentSkill(
            id: id("6E1B0F5A-0000-4000-8000-000000000003"),
            title: "Explain like I have to defend it",
            summary: "Explain something well enough that the user could argue for it themselves.",
            instructions: """
            Explain what the user asks about, aimed at someone who will have to defend the
            explanation to a sceptical colleague an hour from now.

            - Lead with the claim, then the reason it is true.
            - Name the strongest objection and answer it. An explanation that survives no
              objections has not been tested.
            - Say plainly where the evidence is thin, rather than smoothing over it.
            - No analogies unless the analogy is load-bearing; a decorative one gives false
              confidence.

            This skill uses no tools deliberately. It is about the shape of the answer, not
            about fetching anything.
            """,
            allowedToolNames: [],
            isBuiltIn: true
        ),
    ]
}
