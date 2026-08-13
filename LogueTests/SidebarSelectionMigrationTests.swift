import Foundation
@testable import Logue
import Testing

@Suite("SidebarSelectionMigration")
struct SidebarSelectionMigrationTests {
    // MARK: - Surfaces that still exist

    @Test("A stable surface restores to itself and opens no panel")
    func stableSurfacesRestoreUnchanged() {
        let cases: [(String, SidebarItem)] = [
            ("agentChat", .agentChat),
            ("overview", .overview),
            ("pinned", .pinned),
            ("recent", .recent),
            ("allDocuments", .allDocuments),
            ("allMeetings", .allMeetings),
            ("tasks", .tasks),
            ("trash", .trash),
        ]
        for (raw, expected) in cases {
            let restored = SidebarSelectionMigration.restored(from: raw)
            #expect(restored?.item == expected)
            #expect(restored?.panel == nil)
        }
    }

    // MARK: - Surfaces that moved into panels

    /// Without this, anyone whose app last sat on Action Items launches into nothing.
    @Test("A saved Action Items selection lands on All Meetings with its panel open")
    func actionItemsMigratesToMeetings() {
        let restored = SidebarSelectionMigration.restored(from: "actionItems")
        #expect(restored?.item == .allMeetings)
        #expect(restored?.panel == .actionItems)
    }

    @Test("A saved Templates selection lands on All Documents with its panel open")
    func templatesMigratesToDocuments() {
        let restored = SidebarSelectionMigration.restored(from: "templates")
        #expect(restored?.item == .allDocuments)
        #expect(restored?.panel == .templates)
    }

    // MARK: - Unknown input

    @Test("An unrecognised value restores nothing rather than guessing")
    func unknownRestoresNothing() {
        #expect(SidebarSelectionMigration.restored(from: "somethingElse") == nil)
        #expect(SidebarSelectionMigration.restored(from: "") == nil)
    }

    // MARK: - Round trip

    @Test("Every surface that persists a value can be restored from it")
    func persistedValuesAllRestore() {
        let items: [SidebarItem] = [
            .agentChat, .overview, .pinned, .recent,
            .allDocuments, .allMeetings, .tasks, .trash,
        ]
        for item in items {
            let raw = SidebarSelectionMigration.persistedValue(for: item)
            #expect(raw != nil)
            #expect(SidebarSelectionMigration.restored(from: raw ?? "")?.item == item)
        }
    }

    @Test("Per-item selections are not persisted, so they cannot strand a launch")
    func perItemSelectionsAreNotPersisted() {
        let id = UUID()
        #expect(SidebarSelectionMigration.persistedValue(for: .space(id)) == nil)
        #expect(SidebarSelectionMigration.persistedValue(for: .document(id)) == nil)
        #expect(SidebarSelectionMigration.persistedValue(for: .meeting(id)) == nil)
    }
}
