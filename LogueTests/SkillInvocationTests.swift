import Foundation
import Testing
@testable import Logue

/// Reading a skill invocation out of what someone typed.
@Suite("Skill invocation")
struct SkillInvocationTests {
    private let review = AgentSkill(title: "Weekly Review", instructions: "i")
    private let tighten = AgentSkill(title: "Tighten this", instructions: "i")

    private var skills: [AgentSkill] { [review, tighten] }

    private func resolve(_ text: String) -> SkillInvocation.Outcome {
        SkillInvocation.resolve(text, against: skills)
    }

    // MARK: - Reading a name

    @Test("A named skill runs on the rest of the message")
    func namedSkillTakesTheRemainder() {
        #expect(resolve("/weekly-review cover the last week") == .invoked(skill: review, text: "cover the last week"))
    }

    @Test("A name with no message still invokes")
    func nameAloneInvokes() {
        #expect(resolve("/weekly-review") == .invoked(skill: review, text: ""))
    }

    @Test("The name is matched the way it is derived, not literally")
    func nameIsMatchedByDerivation() {
        // A near miss in punctuation or case still lands, because both fold to the same
        // invocation. This is the whole reason the derived name exists.
        #expect(resolve("/weekly_review go") == .invoked(skill: review, text: "go"))
        #expect(resolve("/WEEKLY-REVIEW go") == .invoked(skill: review, text: "go"))
        #expect(resolve("/weekly.review go") == .invoked(skill: review, text: "go"))
    }

    @Test("The name is one token, so typing the title with its space does not invoke")
    func titleWithSpaceIsNotTheName() {
        // `/Weekly Review` reads "Weekly" as the name and "Review" as the message — the
        // space is what separates the two, and it has to be, or there is no way to tell
        // where a name ends and a question begins.
        //
        // This is exactly why the menu shows `/weekly-review` beside the title: what you
        // read and what you type are different strings, and the menu says so.
        #expect(resolve("/Weekly Review") == .unknown(name: "Weekly"))
    }

    @Test("Text with no marker is just a message")
    func plainTextIsAMessage() {
        #expect(resolve("what happened last week") == .none(text: "what happened last week"))
    }

    @Test("A marker in the middle is not an invocation")
    func markerMustLead() {
        // Otherwise "what is 3/4 of this" would try to run a skill called "4".
        #expect(resolve("what is 3/4 of this") == .none(text: "what is 3/4 of this"))
    }

    @Test("A bare marker is someone still typing, not a failure")
    func bareMarkerIsNotAnError() {
        // Putting an error under the cursor before the word is finished is worse than saying
        // nothing yet.
        #expect(resolve("/") == .none(text: "/"))
        #expect(resolve("/ ") == .none(text: "/ "))
    }

    // MARK: - A name that matched nothing

    @Test("An unknown name does not silently become an ordinary message")
    func unknownNameIsItsOwnAnswer() {
        // The failure this rules out: a typo answers a question the user did not ask, with
        // nothing anywhere saying the skill never ran.
        #expect(resolve("/weekly-reveiw do the week") == .unknown(name: "weekly-reveiw"))
    }

    @Test("The message names what was tried")
    func unknownMessageNamesTheAttempt() {
        // "No such skill" leaves the user checking whether they mistyped or never made it.
        #expect(SkillInvocation.unknownMessage(name: "weekly-reveiw").contains("weekly-reveiw"))
    }

    @Test("A hostile name cannot break the message it is quoted in")
    func unknownMessageIsSafe() {
        let message = SkillInvocation.unknownMessage(name: "a\u{202E}b")
        #expect(message.unicodeScalars.contains { $0.value == 0x202E } == false)
    }

    @Test("The named thing is bounded in the message")
    func unknownMessageIsBounded() {
        let message = SkillInvocation.unknownMessage(name: String(repeating: "x", count: 500))
        #expect(message.count < 200)
    }

    // MARK: - Completions

    @Test("A partial name lists what it could become")
    func completionsFilter() {
        #expect(SkillInvocation.completions(for: "week", in: skills).map(\.id) == [review.id])
    }

    @Test("An empty partial lists everything")
    func emptyPartialListsAll() {
        #expect(SkillInvocation.completions(for: "", in: skills).count == 2)
    }

    @Test("The list keeps the store's order, so it does not reshuffle while typing")
    func completionsKeepStoreOrder() {
        // The user is aiming at a position in the list; reordering by closeness of match
        // moves the target as they type.
        #expect(SkillInvocation.completions(for: "t", in: skills).map(\.id) == [tighten.id])
        #expect(SkillInvocation.completions(for: "", in: skills).map(\.id) == [review.id, tighten.id])
    }

    @Test("Nothing matching is an empty list, not everything")
    func noMatchesIsEmpty() {
        #expect(SkillInvocation.completions(for: "zzz", in: skills).isEmpty)
    }
}

/// The whole composer decision, in the one place both surfaces call.
@Suite("Skill turn")
struct SkillTurnTests {
    private let review = AgentSkill(title: "Weekly Review", instructions: "i")
    private var skills: [AgentSkill] { [review] }

    private func turn(_ text: String, armed: AgentSkill? = nil, route: AskRoute = .agentLoop) -> SkillInvocation.Turn {
        SkillInvocation.turn(for: text, armed: armed, route: route, in: skills)
    }

    @Test("A typed name beats an armed chip")
    func typedNameWins() {
        let other = AgentSkill(title: "Tighten this", instructions: "i")
        #expect(turn("/weekly-review go", armed: other) == .send(skill: review, message: "go"))
    }

    @Test("An armed chip is used when nothing is typed")
    func armedChipIsUsed() {
        #expect(turn("do the week", armed: review) == .send(skill: review, message: "do the week"))
    }

    @Test("No skill anywhere sends the text unchanged")
    func plainSend() {
        #expect(turn("do the week") == .send(skill: nil, message: "do the week"))
    }

    @Test("An unknown name refuses rather than sending")
    func unknownRefuses() {
        guard case let .refuse(reason) = turn("/nope go") else {
            Issue.record("an unknown name was sent anyway")
            return
        }
        #expect(reason.contains("nope"))
    }

    @Test("A skill is refused rather than silently dropped on Deep Research")
    func skillAndDeepResearchConflict() {
        // A skill layers onto the agent's prompt and narrows the agent's tools, and a Deep
        // Research run has neither. Dropping it quietly is the same failure as answering an
        // unknown name as a plain message: the user asked for one thing and got another.
        guard case let .refuse(reason) = turn("do the week", armed: review, route: .deepResearch) else {
            Issue.record("the skill was silently dropped")
            return
        }
        #expect(reason.contains("Weekly Review"))
        #expect(reason.contains("Deep Research"))
    }

    @Test("A typed name is refused on Deep Research too")
    func typedNameAndDeepResearchConflict() {
        guard case .refuse = turn("/weekly-review go", route: .deepResearch) else {
            Issue.record("the skill was silently dropped")
            return
        }
    }

    @Test("Image generation is the same answer")
    func skillAndImageConflict() {
        guard case .refuse = turn("a cat", armed: review, route: .imagePlayground(concept: "a cat")) else {
            Issue.record("the skill was silently dropped")
            return
        }
    }

    @Test("Without a skill, another route sends normally")
    func otherRoutesAreFineWithoutASkill() {
        #expect(turn("research this", route: .deepResearch) == .send(skill: nil, message: "research this"))
    }

    @Test("The marker is stripped even when the skill does not apply to the route")
    func markerNeverLeaksIntoAnotherRoute() {
        // The refusal is what the user sees, but the reason this matters is the case above
        // it: a `/name` that reaches a research prompt is a research run on a question with
        // a stray token glued to the front of it.
        #expect(turn("/weekly-review go") == .send(skill: review, message: "go"))
    }
}
