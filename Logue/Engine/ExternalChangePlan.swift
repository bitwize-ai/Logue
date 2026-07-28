import Foundation

/// What a scan of the markdown folder means for the document library.
///
/// Pure, and separate from both the filesystem and the stores, because this is the riskiest
/// rule set in plain-markdown storage: applying a change that did not happen overwrites
/// what the user just typed, and missing one loses what they typed somewhere else.
struct ExternalChangePlan: Sendable {
    /// Documents whose file now says something different.
    var updated: [DocumentContent] = []
    /// Files with no identifier, adopted as new documents.
    var inserted: [DocumentContent] = []
    /// Documents whose file is gone.
    var trashed: [UUID] = []
    /// Identifiers found in files that match no document. Reported, never applied.
    var ignoredIdentifiers: [UUID] = []
    /// Identifiers carried by more than one file, so nothing about them can be applied safely.
    var ambiguousIdentifiers: Set<UUID> = []

    var isEmpty: Bool {
        updated.isEmpty && inserted.isEmpty && trashed.isEmpty
    }

    /// A one-line description for the rescan button's tooltip and the log.
    var summary: String {
        guard !isEmpty else { return "No changes" }
        var parts: [String] = []
        if !updated.isEmpty {
            parts.append("\(updated.count) updated")
        }
        if !inserted.isEmpty {
            parts.append("\(inserted.count) added")
        }
        if !trashed.isEmpty {
            parts.append("\(trashed.count) removed")
        }
        return parts.joined(separator: ", ")
    }
}

enum ExternalChangePlanner {
    /// Compares what the folder holds against what the app holds.
    ///
    /// - Parameters:
    ///   - scanned: documents read from files that carry an identifier.
    ///   - adopted: documents built from files that carry none, with fresh identifiers.
    ///   - known: every document the app has, trashed ones included.
    static func plan(
        scanned: [DocumentContent],
        adopted: [DocumentContent] = [],
        known: [DocumentContent],
        ambiguous: Set<UUID> = []
    ) -> ExternalChangePlan {
        var plan = ExternalChangePlan()
        plan.ambiguousIdentifiers = ambiguous
        let knownByID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var seen: Set<UUID> = []
        for content in scanned where !ambiguous.contains(content.id) {
            // A duplicated file carries a duplicated identifier. The first one wins rather
            // than the two fighting over the document on every scan.
            guard seen.insert(content.id).inserted else { continue }

            guard let existing = knownByID[content.id] else {
                plan.ignoredIdentifiers.append(content.id)
                continue
            }

            // A file naming a document that is in the trash is not an edit to apply. Markdown files
            // carry no trashed flag, so reading one back as an update would clear `isTrashed` and
            // bring the document out of the trash on its own — which happens whenever removing the
            // file failed, or the user put it back from their Trash.
            guard !existing.isTrashed else {
                plan.ignoredIdentifiers.append(content.id)
                continue
            }

            if differs(content, from: existing) {
                plan.updated.append(content)
            }
        }

        plan.inserted = adopted

        // A document with no file is a deletion — but only if the app thinks it should
        // have one. Trashed documents are deliberately absent from the folder, so treating
        // their absence as a deletion would empty the trash on every scan.
        // Ambiguous documents are skipped here as well as above. Their files exist — there are two
        // of them — so trashing them for having none would be the worst possible reading.
        for document in known
            where !document.isTrashed && !seen.contains(document.id)
            && !ambiguous.contains(document.id)
        {
            plan.trashed.append(document.id)
        }

        return plan
    }

    /// Drops updates for documents whose in-memory text changed while the folder was being read.
    ///
    /// A scan reads the folder off the main actor, which takes long enough for the user to type. An
    /// update built from the snapshot taken beforehand would put the file's older text back over
    /// what they just wrote — the one failure this feature cannot be allowed to have. Dropping it
    /// costs a scan: the next one diffs against the newer text and applies whatever is still true.
    static func discardingUpdatesThatMovedOn(
        _ plan: ExternalChangePlan,
        comparedTo snapshot: [DocumentContent],
        current: [DocumentContent]
    ) -> ExternalChangePlan {
        guard !plan.updated.isEmpty else { return plan }

        let snapshotByID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var settled = plan
        settled.updated = plan.updated.filter { update in
            guard let before = snapshotByID[update.id], let now = currentByID[update.id] else {
                // Gone from memory entirely, or never there: leave it to the next scan rather than
                // guess.
                return false
            }
            return !differs(now, from: before)
        }
        return settled
    }

    /// Whether a file's content differs from the document in a way worth applying.
    ///
    /// Timestamps are deliberately excluded. An external editor rewrites the body without
    /// touching `modified:`, and our own writes bump it — so comparing timestamps would
    /// both miss real edits and manufacture fake ones. Only what the markdown actually
    /// represents is compared.
    static func differs(_ scanned: DocumentContent, from known: DocumentContent) -> Bool {
        scanned.title != known.title
            || scanned.body != known.body
            || scanned.tags != known.tags
            || scanned.spaceID != known.spaceID
            || scanned.icon != known.icon
            || scanned.isPinned != known.isPinned
            || scanned.properties ?? [:] != known.properties ?? [:]
            || scanned.relationships ?? [:] != known.relationships ?? [:]
    }
}
