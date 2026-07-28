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
    private func document(_ title: String, body: String = "body", trashed: Bool = false) -> DocumentContent {
        var doc = WritingDocument()
        doc.title = title
        doc.body = body
        doc.isTrashed = trashed
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

    // MARK: - Deletions that moved on

    /// The counterpart to dropping a stale update, and the more dangerous of the two: trashing a
    /// document takes its file with it. A batch imported while the folder was being read is absent
    /// from that walk for the one reason that is not a deletion.
    @Test("A document created during the walk is not trashed for being absent from it")
    func createdDuringWalkSurvives() {
        let existed = document("Existed")
        let createdSince = document("Created since")

        var plan = ExternalChangePlan()
        plan.trashed = [createdSince.id]

        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: [existed], current: [existed, createdSince]
        )
        #expect(settled.trashed.isEmpty)
        #expect(kept == [createdSince.id])
    }

    /// Restoring writes the file, but the walk has already been and the existence cross-check
    /// reads the same snapshot — so nothing else notices. Trashing it again ran `removeFile` over
    /// the file the restore had just written.
    @Test("A document restored during the walk is not trashed again")
    func restoredDuringWalkSurvives() {
        let trashed = document("Restored", trashed: true)
        var restored = trashed
        restored.isTrashed = false

        var plan = ExternalChangePlan()
        plan.trashed = [trashed.id]

        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: [trashed], current: [restored]
        )
        #expect(settled.trashed.isEmpty)
        #expect(kept == [trashed.id])
    }

    /// The exemption is for a document that *came back*, not for one that is still in the trash.
    @Test("A document still trashed at the end of the walk is not rescued")
    func stillTrashedIsNotRescued() {
        let trashed = document("Trashed", trashed: true)
        var plan = ExternalChangePlan()
        plan.trashed = [trashed.id]

        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: [trashed], current: [trashed]
        )
        #expect(settled.trashed == [trashed.id])
        #expect(kept.isEmpty)
    }

    @Test("A document that existed before the walk and has no file is still trashed")
    func predatingDeletionStillApplies() {
        let gone = document("Gone")
        var plan = ExternalChangePlan()
        plan.trashed = [gone.id]

        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: [gone], current: [gone]
        )
        #expect(settled.trashed == [gone.id])
        #expect(kept.isEmpty)
    }

    /// Rescuing one must not suspend deletion for the rest, or one mid-scan import would freeze
    /// external deletions for the whole library.
    @Test("Rescuing a new document still lets a real deletion through")
    func rescueIsScoped() {
        let gone = document("Gone")
        let createdSince = document("Created since")
        var plan = ExternalChangePlan()
        plan.trashed = [gone.id, createdSince.id]

        let (settled, kept) = ExternalChangePlanner.keepingDeletionsThatMovedOn(
            plan, baseline: [gone], current: [gone, createdSince]
        )
        #expect(settled.trashed == [gone.id])
        #expect(kept == [createdSince.id])
    }

    /// The finding that started this: an edit landing during the *walk* was compared against a
    /// baseline read after it, so it looked settled and the file's older text won.
    @Test("An edit made during the walk is not overwritten by the file")
    func editDuringWalkIsHeldBack() {
        let beforeWalk = document("Note", body: "A")
        var typedSince = beforeWalk
        typedSince.body = "B"

        var fromFile = beforeWalk
        fromFile.body = "A"

        var plan = ExternalChangePlan()
        plan.updated = [fromFile]

        // Compared against the pre-walk baseline, the document moved on, so the update is dropped.
        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [beforeWalk], current: [typedSince]
        )
        #expect(settled.updated.isEmpty)
    }

    /// The same document dragged to another space during the walk. `differs` fires on `spaceID`,
    /// so without the pre-walk baseline the move was undone.
    @Test("A space move made during the walk is not undone")
    func spaceMoveDuringWalkIsHeldBack() {
        let beforeWalk = document("Note")
        var movedSince = beforeWalk
        movedSince.spaceID = UUID()

        var plan = ExternalChangePlan()
        plan.updated = [beforeWalk]

        let settled = ExternalChangePlanner.discardingUpdatesThatMovedOn(
            plan, comparedTo: [beforeWalk], current: [movedSince]
        )
        #expect(settled.updated.isEmpty)
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
