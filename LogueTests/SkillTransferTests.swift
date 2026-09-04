import Testing
@testable import Logue

/// What an import says happened.
///
/// The counts are the easy thing to get wrong here — "1 skills" is the kind of detail that
/// nobody notices until it ships, and "imported 0" reading the same as "imported nothing at
/// all" is the kind that makes a user press the button again.
@Suite("Skill transfer")
@MainActor
struct SkillTransferTests {
    @Test("Everything landing says so plainly")
    func allImported() {
        #expect(SkillTransfer.summary(taken: 3, chosen: 3) == "Imported 3 skills.")
    }

    @Test("One is singular")
    func singular() {
        #expect(SkillTransfer.summary(taken: 1, chosen: 1) == "Imported 1 skill.")
        #expect(SkillTransfer.summary(taken: 0, chosen: 1) == "Nothing could be imported from 1 file.")
    }

    @Test("A partial import says how many of how many")
    func partialImport() {
        // The number that matters is what did *not* arrive — a bare "imported 2" beside a
        // selection of five reads as success.
        #expect(SkillTransfer.summary(taken: 2, chosen: 5) == "Imported 2 skills of 5.")
    }

    @Test("Nothing landing is said out loud")
    func nothingImported() {
        // An import that quietly does nothing is indistinguishable from one that worked.
        #expect(SkillTransfer.summary(taken: 0, chosen: 4) == "Nothing could be imported from 4 files.")
    }

    @Test("Every count reads as a sentence, at every size")
    func everyCountIsWellFormed() {
        for chosen in 0 ... 12 {
            for taken in 0 ... chosen {
                let text = SkillTransfer.summary(taken: taken, chosen: chosen)
                #expect(text.hasSuffix("."), "not a sentence: \(text)")
                #expect(text.contains(" 1 skills") == false, "bad plural: \(text)")
                #expect(text.contains(" 1 files") == false, "bad plural: \(text)")
            }
        }
    }

    @Test("A skill file can be read back out of what export writes")
    func exportRoundTrips() throws {
        // `export` writes `SkillFile.render`; this is the pairing that makes sharing work,
        // asserted without touching a panel or the filesystem.
        let skill = AgentSkill(
            title: "Weekly Review",
            summary: "s",
            instructions: "Body.",
            allowedToolNames: ["get_document"]
        )
        let parsed = try #require(SkillFile.parse(SkillFile.render(skill)))
        #expect(parsed.title == skill.title)
        #expect(parsed.allowedToolNames == skill.allowedToolNames)
    }
}
