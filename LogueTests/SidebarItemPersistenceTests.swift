import Foundation
@testable import Logue
import Testing

/// Which surface a relaunch lands on. Home used to be two separate items and both
/// spellings are already written to disk on users' machines, so the property worth
/// guarding is that neither one strands an upgrading user somewhere they did not leave.
@Suite("SidebarItemPersistence")
struct SidebarItemPersistenceTests {
    @Test("Both retired spellings migrate to the merged surface")
    func retiredSpellingsMigrate() {
        #expect(SidebarItemPersistence.item(forStored: "overview") == .home)
        #expect(SidebarItemPersistence.item(forStored: "agentChat") == .home)
    }

    @Test("The current spelling round-trips")
    func currentSpellingRoundTrips() {
        #expect(SidebarItemPersistence.stored(for: .home) == "home")
        #expect(SidebarItemPersistence.item(forStored: "home") == .home)
    }

    @Test("Every other stable surface still round-trips")
    func otherSurfacesRoundTrip() {
        let surfaces: [SidebarItem] = [
            .pinned, .recent, .allDocuments, .allMeetings, .actionItems, .templates, .trash,
        ]
        for surface in surfaces {
            guard let raw = SidebarItemPersistence.stored(for: surface) else {
                Issue.record("\(surface) produced no stored value")
                continue
            }
            #expect(SidebarItemPersistence.item(forStored: raw) == surface)
        }
    }

    @Test("Per-item selections are not persisted")
    func perItemSelectionsAreNotPersisted() {
        #expect(SidebarItemPersistence.stored(for: .document(UUID())) == nil)
        #expect(SidebarItemPersistence.stored(for: .meeting(UUID())) == nil)
        #expect(SidebarItemPersistence.stored(for: .space(UUID())) == nil)
        #expect(SidebarItemPersistence.stored(for: nil) == nil)
    }

    @Test("An unrecognised value is not guessed at")
    func unrecognisedValuesAreNotGuessed() {
        #expect(SidebarItemPersistence.item(forStored: "wat") == nil)
        #expect(SidebarItemPersistence.item(forStored: "") == nil)
    }
}
