import Foundation
@testable import Logue
import Testing

/// Deciding what a change on disk means for the library.
///
/// The two failures this guards are asymmetric but both bad: applying a change that did not
/// happen overwrites what the user just typed, and ignoring one loses what they typed in
/// another editor. Every rule below exists because one of those is possible without it.
@Suite("External change plan")
struct ExternalChangePlanTests {
    private func document(_ title: String, body: String = "body", trashed: Bool = false) -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        doc.isTrashed = trashed
        return doc.content
    }

    // MARK: - No change

    /// The most important case: a file that matches must produce nothing, or a scan turns
    /// into a write, which turns into a scan.
    @Test("An unchanged file produces no change")
    func unchangedFileIsQuiet() {
        let doc = document("Alpha")
        let plan = ExternalChangePlanner.plan(scanned: [doc], known: [doc])

        #expect(plan.isEmpty)
        #expect(plan.summary == "No changes")
    }

    @Test("An empty folder with no documents produces no change")
    func emptyIsQuiet() {
        #expect(ExternalChangePlanner.plan(scanned: [], known: []).isEmpty)
    }

    /// Our own writes bump `modified:`; an external editor does not touch it. Comparing it
    /// would both invent changes and hide them.
    @Test("A differing timestamp alone is not a change")
    func timestampAloneIsNotAChange() {
        var known = document("Alpha")
        var scanned = known
        scanned.modifiedAt = known.modifiedAt.addingTimeInterval(500)
        known.createdAt = known.createdAt.addingTimeInterval(-500)

        #expect(ExternalChangePlanner.plan(scanned: [scanned], known: [known]).isEmpty)
    }

    // MARK: - Updates

    @Test("An edited body is an update")
    func editedBodyUpdates() throws {
        let known = document("Alpha", body: "old")
        var scanned = known
        scanned.body = "new"

        let plan = ExternalChangePlanner.plan(scanned: [scanned], known: [known])
        #expect(plan.updated.count == 1)
        #expect(try #require(plan.updated.first).body == "new")
        #expect(plan.trashed.isEmpty)
    }

    @Test("A retitled file is an update")
    func editedTitleUpdates() {
        let known = document("Alpha")
        var scanned = known
        scanned.title = "Renamed"

        #expect(ExternalChangePlanner.plan(scanned: [scanned], known: [known]).updated.count == 1)
    }

    /// Moving a file between folders is how the user refiles a document from Finder.
    @Test("A file moved to another folder is an update")
    func movedFileUpdates() {
        let known = document("Alpha")
        var scanned = known
        scanned.spaceID = UUID()

        #expect(ExternalChangePlanner.plan(scanned: [scanned], known: [known]).updated.count == 1)
    }

    @Test("Changed tags, properties and relationships are updates")
    func metadataUpdates() {
        let known = document("Alpha")

        var tagged = known
        tagged.tags = ["draft"]
        var propertied = known
        propertied.properties = ["status": .text("done")]
        var related = known
        related.relationships = ["blocks": ["Beta"]]

        for scanned in [tagged, propertied, related] {
            #expect(ExternalChangePlanner.plan(scanned: [scanned], known: [known]).updated.count == 1)
        }
    }

    // MARK: - Deletion

    @Test("A document whose file is gone is trashed")
    func missingFileTrashes() {
        let gone = document("Gone")
        let plan = ExternalChangePlanner.plan(scanned: [], known: [gone])

        #expect(plan.trashed == [gone.id])
    }

    /// Trashed documents have no file on purpose. Reading their absence as a deletion would
    /// re-trash them on every single scan.
    @Test("An already-trashed document is not trashed again")
    func trashedStaysPut() {
        let plan = ExternalChangePlanner.plan(scanned: [], known: [document("Deleted", trashed: true)])

        #expect(plan.isEmpty)
    }

    /// A document whose write failed has no file because we could not make one, not because the
    /// user removed it. Trashing it would turn a full disk into a deletion.
    @Test("A document whose write failed is not read as a deletion")
    func failedWriteIsNotADeletion() {
        let unwritten = document("Could not be written")
        let plan = ExternalChangePlanner.plan(
            scanned: [], known: [unwritten], withoutFiles: [unwritten.id]
        )

        #expect(plan.trashed.isEmpty)
        #expect(plan.unwalkable == [unwritten.id])
    }

    /// The exemption has to be per-document, or one failed write would freeze deletions for the
    /// whole library.
    @Test("Exempting a failed write still lets a real deletion through")
    func failedWriteExemptionIsScoped() {
        let unwritten = document("Could not be written")
        let gone = document("Gone")
        let plan = ExternalChangePlanner.plan(
            scanned: [], known: [unwritten, gone], withoutFiles: [unwritten.id]
        )

        #expect(plan.trashed == [gone.id])
    }

    @Test("Deleting one file leaves the others alone")
    func deletionIsScoped() {
        let kept = document("Kept")
        let gone = document("Gone")

        let plan = ExternalChangePlanner.plan(scanned: [kept], known: [kept, gone])
        #expect(plan.trashed == [gone.id])
        #expect(plan.updated.isEmpty)
    }

    // MARK: - New files

    @Test("A file with no identifier is inserted as a new document")
    func adoptedFileInserts() {
        let dropped = document("Dropped in")
        let plan = ExternalChangePlanner.plan(scanned: [], adopted: [dropped], known: [])

        #expect(plan.inserted.count == 1)
        #expect(plan.isEmpty == false)
    }

    /// An identifier matching no document is most likely a file left behind by something
    /// outside the app. Adopting it would resurrect a document; the safe answer is to say so
    /// and do nothing.
    @Test("An unknown identifier is reported, not imported")
    func unknownIdentifierIgnored() {
        let stranger = document("Stranger")
        let plan = ExternalChangePlanner.plan(scanned: [stranger], known: [])

        #expect(plan.ignoredIdentifiers == [stranger.id])
        #expect(plan.inserted.isEmpty)
        #expect(plan.updated.isEmpty)
    }

    /// Copying a file in Finder duplicates its identifier. Both copies claiming the document
    /// would make each scan overwrite the other's text.
    @Test("A duplicated identifier is applied once")
    func duplicateIdentifierAppliedOnce() {
        let known = document("Alpha", body: "old")
        var first = known
        first.body = "first"
        var second = known
        second.body = "second"

        let plan = ExternalChangePlanner.plan(scanned: [first, second], known: [known])
        #expect(plan.updated.count == 1)
        #expect(plan.trashed.isEmpty)
    }

    // MARK: - Summary

    @Test("The summary names what changed")
    func summaryDescribesPlan() {
        let edited = document("Alpha", body: "old")
        var scanned = edited
        scanned.body = "new"

        let plan = ExternalChangePlanner.plan(
            scanned: [scanned],
            adopted: [document("New")],
            known: [edited, document("Gone")]
        )

        #expect(plan.summary.contains("1 updated"))
        #expect(plan.summary.contains("1 added"))
        #expect(plan.summary.contains("1 removed"))
    }
}

/// Holding back an update for a document the user edited while the folder was being read.
///
/// A scan reads the folder off the main actor. If the user types during that read, applying an
/// update built from the earlier snapshot puts the file's older text back over what they wrote —
/// the one failure this feature cannot have.
@Suite("Concurrent edit protection")
struct ConcurrentEditProtectionTests {
    private func document(_ title: String, body: String) -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        return doc.content
    }

    @Test("An update survives when the document has not changed since the snapshot")
    func unchangedDocumentKeepsUpdate() {
        let snapshot = document("Alpha", body: "old")
        var fromFile = snapshot
        fromFile.body = "from the file"

        var plan = ExternalChangePlan()
        plan.updated = [fromFile]

        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [snapshot], current: [snapshot]
        )
        #expect(settled.updated.count == 1)
    }

    @Test("An update is dropped when the user typed during the scan")
    func editedDocumentDropsUpdate() {
        let snapshot = document("Alpha", body: "old")
        var fromFile = snapshot
        fromFile.body = "from the file"
        var typedSince = snapshot
        typedSince.body = "what the user just typed"

        var plan = ExternalChangePlan()
        plan.updated = [fromFile]

        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [snapshot], current: [typedSince]
        )
        #expect(settled.updated.isEmpty)
    }

    @Test("Dropping one update leaves the others, and insertions and deletions alone")
    func dropIsScoped() {
        let steady = document("Steady", body: "same")
        let edited = document("Edited", body: "old")
        var editedSince = edited
        editedSince.body = "typed"

        var steadyFromFile = steady
        steadyFromFile.body = "from the file"
        var editedFromFile = edited
        editedFromFile.body = "from the file"

        var plan = ExternalChangePlan()
        plan.updated = [steadyFromFile, editedFromFile]
        plan.inserted = [document("New", body: "new")]
        plan.trashed = [UUID()]

        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [steady, edited], current: [steady, editedSince]
        )

        #expect(settled.updated.map(\.id) == [steady.id])
        #expect(settled.inserted.count == 1)
        #expect(settled.trashed.count == 1)
    }

    @Test("A document that vanished from memory during the scan is left for the next one")
    func missingDocumentDropsUpdate() {
        let snapshot = document("Alpha", body: "old")
        var fromFile = snapshot
        fromFile.body = "from the file"

        var plan = ExternalChangePlan()
        plan.updated = [fromFile]

        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [snapshot], current: []
        )
        #expect(settled.updated.isEmpty)
    }

    @Test("An empty plan is returned untouched")
    func emptyPlanUnchanged() {
        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            ExternalChangePlan(), comparedTo: [], current: []
        )
        #expect(settled.isEmpty)
    }
}
