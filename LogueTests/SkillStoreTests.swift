import Foundation
import Testing
@testable import Logue

/// The skill list: what it accepts, what it refuses, and how a built-in survives being edited.
@Suite("Skill store")
@MainActor
struct SkillStoreTests {
    private func scratch(_ name: String) -> SkillStore {
        let suite = UserDefaults(suiteName: name)
        suite?.removePersistentDomain(forName: name)
        return SkillStore(
            defaults: suite ?? .standard,
            key: "\(name).skills",
            overrideKey: "\(name).overrides"
        )
    }

    // MARK: - Built-ins

    @Test("The built-ins are there to be read")
    func builtInsArePresent() {
        let store = scratch("skills.builtins")
        #expect(store.skills.isEmpty == false)
        #expect(store.skills.allSatisfy { $0.isBuiltIn })
    }

    @Test("Every built-in can actually be invoked")
    func builtInsAreInvocable() {
        // A built-in whose title derives to nothing would be an example nobody can run —
        // worse than no example, because it teaches the wrong thing.
        let store = scratch("skills.invocable")
        for skill in store.skills {
            #expect(skill.invocation.isEmpty == false, "\(skill.title) has no invocation")
            #expect(store.skill(invokedBy: skill.invocation)?.id == skill.id)
        }
    }

    @Test("No two built-ins share an invocation")
    func builtInsDoNotCollide() {
        let names = SkillCatalog.builtIns.map(\.invocation)
        #expect(Set(names).count == names.count)
    }

    @Test("Editing a built-in does not destroy it")
    func editingABuiltInIsReversible() throws {
        // The built-ins are documentation as much as features; someone who overwrote the only
        // worked example must have a way back.
        let store = scratch("skills.edit")
        var original = try #require(store.skills.first)
        let originalInstructions = original.instructions

        original.instructions = "Something else entirely."
        #expect(store.update(original).isSuccess)
        #expect(store.skill(invokedBy: original.invocation)?.instructions == "Something else entirely.")

        store.restore(id: original.id)
        #expect(store.skill(invokedBy: original.invocation)?.instructions == originalInstructions)
    }

    @Test("An edited built-in appears once, not twice")
    func editedBuiltInIsNotDuplicated() throws {
        let store = scratch("skills.nodupe")
        var original = try #require(store.skills.first)
        original.summary = "Changed"
        #expect(store.update(original).isSuccess)
        #expect(store.skills.count { $0.id == original.id } == 1)
    }

    // MARK: - Names

    @Test("A skill that would be invoked like an existing one is refused")
    func duplicateInvocationIsRefused() {
        let store = scratch("skills.dupe")
        #expect(store.add(AgentSkill(title: "Weekly Review", instructions: "x")).isSuccess)
        let second = store.add(AgentSkill(title: "weekly-review", instructions: "y"))
        #expect(second.isSuccess == false)
    }

    @Test("A file cannot declare itself a built-in and become unremovable")
    func addedSkillIsNeverBuiltIn() throws {
        let store = scratch("skills.claim")
        let added = try #require(store.add(AgentSkill(title: "Sneaky", instructions: "x", isBuiltIn: true)).value)
        #expect(added.isBuiltIn == false)
        store.remove(id: added.id)
        #expect(store.skill(invokedBy: "sneaky") == nil)
    }

    // MARK: - Import

    @Test("A colliding import is renamed rather than dropped")
    func importRenamesRatherThanRefusing() {
        // Someone importing six skills should not have to discover a clash, fix it and start
        // over — and silently dropping one is worse than either.
        let store = scratch("skills.import")
        let file = "---\nname: Weekly Review\n---\nDo the week."
        #expect(store.importSkills(from: [file, file]) == 2)
        #expect(store.skills.count { $0.title.hasPrefix("Weekly Review") } == 2)
    }

    @Test("A malformed file costs that skill, not the import")
    func malformedFileDoesNotStopTheImport() {
        let store = scratch("skills.partial")
        let good = "---\nname: Good\n---\nBody."
        #expect(store.importSkills(from: ["", good, "---\n---\n"]) == 1)
        #expect(store.skill(invokedBy: "good") != nil)
    }

    @Test("An exported skill imports back")
    func exportImportsBack() throws {
        let store = scratch("skills.export")
        let added = try #require(store.add(AgentSkill(
            title: "Roundtrip",
            summary: "s",
            instructions: "Body.",
            allowedToolNames: ["get_document"]
        )).value)

        let elsewhere = scratch("skills.export.other")
        #expect(elsewhere.importSkills(from: [store.exportText(for: added)]) == 1)
        let landed = try #require(elsewhere.skill(invokedBy: "roundtrip"))
        #expect(landed.instructions == "Body.")
        #expect(landed.allowedToolNames == ["get_document"])
    }

    // MARK: - Persistence

    @Test("Skills survive a relaunch")
    func skillsPersist() {
        let name = "skills.persist"
        let store = scratch(name)
        #expect(store.add(AgentSkill(title: "Kept", instructions: "x")).isSuccess)

        let reopened = SkillStore(
            defaults: UserDefaults(suiteName: name) ?? .standard,
            key: "\(name).skills",
            overrideKey: "\(name).overrides"
        )
        #expect(reopened.skill(invokedBy: "kept") != nil)
    }

    @Test("An override survives a relaunch, so an edited built-in stays edited")
    func overridesPersist() throws {
        let name = "skills.override.persist"
        let store = scratch(name)
        var original = try #require(store.skills.first)
        original.instructions = "Mine."
        #expect(store.update(original).isSuccess)

        let reopened = SkillStore(
            defaults: UserDefaults(suiteName: name) ?? .standard,
            key: "\(name).skills",
            overrideKey: "\(name).overrides"
        )
        #expect(reopened.skills.count { $0.id == original.id } == 1)
        #expect(reopened.skill(invokedBy: original.invocation)?.instructions == "Mine.")
    }

    @Test("Unreadable stored data reads as no user skills, not as a crash")
    func corruptDataIsSurvived() {
        let name = "skills.corrupt"
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        defaults?.set(Data("not json".utf8), forKey: "\(name).skills")

        let store = SkillStore(
            defaults: defaults ?? .standard,
            key: "\(name).skills",
            overrideKey: "\(name).overrides"
        )
        #expect(store.userSkills.isEmpty)
        #expect(store.skills.isEmpty == false, "the built-ins are still there")
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var value: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}
