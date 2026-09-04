import Foundation

/// Reading a skill invocation out of what the user typed.
///
/// #64 says a skill is invoked **by name**, so typing it has to work — a picker alone means
/// the fastest way to run a saved instruction is to reach for the mouse. `/weekly-review do
/// the last week` runs that skill on "do the last week".
///
/// Pure, and not a method on either composer, for the reason `AskRouter` is: a decision made
/// inside a `View` is one the other surface cannot reach, and this one has to be identical
/// on both. `AskSurface` is deliberately not an input.
enum SkillInvocation {
    /// The character that starts an invocation.
    static let marker: Character = "/"

    /// What the text turned out to be.
    enum Outcome: Equatable {
        /// No invocation was attempted. The text is the message.
        case none(text: String)
        /// A skill was named and found. The text is what remains after the name.
        case invoked(skill: AgentSkill, text: String)
        /// A skill was named and not found.
        ///
        /// Deliberately its own case rather than falling back to `.none`. Someone who typed
        /// `/weekly-reveiw` meant to run something; sending it to the model as an ordinary
        /// message produces a confident answer to a question they did not ask, and nothing
        /// anywhere says the skill did not run. The composer refuses and names what it tried.
        case unknown(name: String)
    }

    /// Reads `text` as a possible invocation.
    ///
    /// - Parameter skills: everything invocable, in the order the store lists it.
    static func resolve(_ text: String, against skills: [AgentSkill]) -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == marker else { return .none(text: text) }

        let afterMarker = trimmed.dropFirst()
        // The name ends at the first whitespace; everything after it is the message.
        let split = afterMarker.firstIndex(where: { $0.isWhitespace })
        let rawName = String(afterMarker[afterMarker.startIndex ..< (split ?? afterMarker.endIndex)])
        let remainder = split.map { String(afterMarker[afterMarker.index(after: $0)...]) } ?? ""

        // A bare "/" is someone who has started typing, not a failed invocation. Treating it
        // as unknown would put an error under the cursor before they had finished the word.
        guard !rawName.isEmpty else { return .none(text: text) }

        let wanted = SkillName.invocation(from: rawName)
        guard let skill = skills.first(where: { $0.invocation == wanted }) else {
            return .unknown(name: rawName)
        }
        return .invoked(skill: skill, text: remainder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What a composer should actually do with what was typed.
    ///
    /// The whole decision in one place: read the name, pick between a typed name and an
    /// armed chip, and settle whether a skill applies to this route at all. Both composers
    /// call this and neither re-derives any of it — the precedence rule written twice is the
    /// per-surface drift the rest of #61 exists to stop.
    enum Turn: Equatable {
        /// Send it. `skill` is nil when none applies.
        case send(skill: AgentSkill?, message: String)
        /// Do not send. Show this.
        case refuse(reason: String)
    }

    /// - Parameters:
    ///   - armed: the skill armed by the chip, if any.
    ///   - route: where this send is going. A skill only applies to the agent loop.
    static func turn(
        for text: String,
        armed: AgentSkill?,
        route: AskRoute,
        in skills: [AgentSkill]
    ) -> Turn {
        let message: String
        let skill: AgentSkill?

        switch resolve(text, against: skills) {
        case let .unknown(name):
            return .refuse(reason: unknownMessage(name: name))
        case let .invoked(found, remainder):
            // A typed name wins over an armed chip: it is the more specific instruction, and
            // the one under the cursor as Return is pressed.
            (skill, message) = (found, remainder)
        case let .none(plain):
            (skill, message) = (armed, plain)
        }

        // A skill layers onto the agent's system prompt and narrows the agent's tools —
        // neither of which a Deep Research run or an image generation has. Dropping it
        // silently would be the same failure as answering an unknown name as a plain
        // message: the user asked for something and got something else, with nothing saying
        // so. Refused, and named.
        if let skill, route != .agentLoop {
            return .refuse(reason: doesNotApplyMessage(skill: skill, route: route))
        }
        return .send(skill: skill, message: message)
    }

    /// Why a skill was not run for this send.
    static func doesNotApplyMessage(skill: AgentSkill, route: AskRoute) -> String {
        let what = switch route {
        case .deepResearch: "Deep Research"
        case .imagePlayground: "image generation"
        case .agentLoop: "this"
        }
        return "“\(SkillName.title(from: skill.title))” can't be used with \(what). "
            + "Turn one of them off and send again."
    }

    /// What to say when a name matched nothing.
    ///
    /// Names the thing that was tried. "No such skill" leaves the user checking whether they
    /// mistyped the name or never made the skill.
    static func unknownMessage(name: String) -> String {
        "No skill called “\(DisplayText.clamp(DisplayText.singleLine(name), to: 40))”. "
            + "Type / to see the ones you have."
    }

    /// Skills whose invocation begins with a partly-typed name, for a completion list.
    ///
    /// Ordered by the store, not by closeness of match: the list must not reshuffle under
    /// the user as they type, because they are aiming at a position in it.
    static func completions(for partial: String, in skills: [AgentSkill]) -> [AgentSkill] {
        let wanted = SkillName.invocation(from: partial)
        guard !wanted.isEmpty else { return skills }
        return skills.filter { $0.invocation.hasPrefix(wanted) }
    }
}
