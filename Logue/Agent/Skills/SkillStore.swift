import Foundation
import os.log

/// The skills the user has, and the built-ins they can read as examples.
///
/// `UserDefaults`, like `MCPServerStore`: a skill is text the user wrote, not a secret, and
/// the project rule is that only secrets go in the Keychain. Injectable defaults so the rules
/// are testable against a scratch suite rather than the user's own settings.
@MainActor
@Observable
final class SkillStore {
    static let shared = SkillStore()

    /// Everything invocable, built-ins first so the examples are what a new user sees.
    ///
    /// An edited built-in is rendered **in the built-in's place**, not appended. Editing the
    /// summary of the first skill in the list should not send it to the bottom of a picker.
    var skills: [AgentSkill] {
        let edits = Dictionary(userSkills.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let builtInIDs = Set(SkillCatalog.builtIns.map(\.id))
        return SkillCatalog.builtIns.map { edits[$0.id] ?? $0 }
            + userSkills.filter { !builtInIDs.contains($0.id) }
    }

    private(set) var userSkills: [AgentSkill] = []

    /// Built-ins the user has edited — **derived**, never stored.
    ///
    /// Editing a built-in copies it rather than changing it: the built-ins are documentation
    /// as much as they are features, and someone who overwrote the only worked example has no
    /// way back. A user skill carrying a built-in's id *is* that override, which makes this a
    /// question about `userSkills` rather than a second thing to keep in step with it.
    ///
    /// It was a stored `Set<UUID>` first, and that is a state pair that can disagree: the two
    /// blobs are read separately, so a corrupt skills list read as empty while the override
    /// list read fine would hide a built-in with nothing standing in for it — the skill would
    /// simply be gone, with no way back that does not involve editing defaults.
    var overriddenBuiltInIDs: Set<UUID> {
        let builtInIDs = Set(SkillCatalog.builtIns.map(\.id))
        return Set(userSkills.map(\.id)).intersection(builtInIDs)
    }

    private let defaults: UserDefaults
    private let key: String
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "Skills")

    init(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.agentSkills
    ) {
        self.defaults = defaults
        self.key = key
        userSkills = Self.load(from: defaults, key: key, logger: logger)
    }

    // MARK: - Reading

    func skill(invokedBy name: String) -> AgentSkill? {
        let wanted = SkillName.invocation(from: name)
        guard !wanted.isEmpty else { return nil }
        return skills.first { $0.invocation == wanted }
    }

    /// The titles of every skill except one, for `SkillName.validate`.
    func otherTitles(excluding id: UUID?) -> [String] {
        skills.filter { $0.id != id }.map(\.title)
    }

    // MARK: - Writing

    /// Adds a skill, refusing a title that is empty or already taken.
    @discardableResult
    func add(_ skill: AgentSkill) -> Result<AgentSkill, SkillName.Rejection> {
        switch SkillName.validate(skill.title, against: otherTitles(excluding: nil)) {
        case let .failure(rejection):
            return .failure(rejection)
        case let .success(title):
            var stored = skill
            stored.title = title
            // Never trusted from the caller: a file cannot declare itself a built-in and
            // become unremovable, or shadow one of ours.
            stored.isBuiltIn = false
            userSkills.append(stored)
            persist()
            return .success(stored)
        }
    }

    @discardableResult
    func update(_ skill: AgentSkill) -> Result<AgentSkill, SkillName.Rejection> {
        switch SkillName.validate(skill.title, against: otherTitles(excluding: skill.id)) {
        case let .failure(rejection):
            return .failure(rejection)
        case let .success(title):
            var stored = skill
            stored.title = title
            stored.isBuiltIn = false
            if let index = userSkills.firstIndex(where: { $0.id == skill.id }) {
                userSkills[index] = stored
            } else {
                // Editing a built-in. Keeping its id is the whole mechanism: the stored copy
                // stands in for the original wherever the original would have appeared, and
                // removing it is what brings the original back.
                userSkills.append(stored)
            }
            persist()
            return .success(stored)
        }
    }

    func remove(id: UUID) {
        userSkills.removeAll { $0.id == id }
        // Removing an edited built-in brings the original back, because the original was
        // never gone — only stood in for. That is what makes editing one safe to try.
        persist()
    }

    /// Puts a built-in back the way it shipped.
    func restore(id: UUID) {
        guard overriddenBuiltInIDs.contains(id) else { return }
        remove(id: id)
    }

    // MARK: - Import and export

    /// Imports skills from files' text, returning how many were taken.
    ///
    /// A malformed file costs that skill, never the whole import, and a title that collides
    /// is renamed rather than refused — someone importing six skills should not have to
    /// discover the clash, fix it and start again.
    @discardableResult
    func importSkills(from texts: [String]) -> Int {
        var taken = 0
        for text in texts {
            guard let parsed = SkillFile.parse(text) else {
                logger.error("Skipped a skill file that had neither a name nor a body")
                continue
            }
            var candidate = parsed
            candidate.title = uniqueTitle(from: parsed.title)
            if case .success = add(candidate) {
                taken += 1
            }
        }
        return taken
    }

    func exportText(for skill: AgentSkill) -> String {
        SkillFile.render(skill)
    }

    /// A title nothing else is using, by adding a counter rather than refusing.
    private func uniqueTitle(from wanted: String) -> String {
        let existing = otherTitles(excluding: nil)
        guard case .failure = SkillName.validate(wanted, against: existing) else { return wanted }
        // Bounded: a suffix that never terminates would be a hang, not a rename.
        for suffix in 2 ... 99 {
            let candidate = "\(wanted) \(suffix)"
            if case .success = SkillName.validate(candidate, against: existing) {
                return candidate
            }
        }
        return "\(wanted) \(UUID().uuidString.prefix(8))"
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(userSkills), forKey: key)
        } catch {
            logger.error("Could not save skills: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults, key: String, logger: Logger) -> [AgentSkill] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([AgentSkill].self, from: data)
        } catch {
            // Empty is the safe failure here in the same sense it is for servers: a skill the
            // user cannot see is a skill that cannot silently steer a turn.
            logger.error("Could not read skills: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
